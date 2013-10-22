require 'fog'
#require 'excon'
#require 'nokogiri'
require 'thread'

module Deltacloud
  module Drivers
    module Vcloud

class VcloudDriver < Deltacloud::BaseDriver
  feature :instances, :user_name do
    { :max_length => 50 }
  end
  
  define_hardware_profile('default')
  
  def hardware_profiles(credentials, opts = {})
    # TODO: Instead of hard-coding the hardware profile values, they should be kept in some external location (like file or some service), and read from there
    @hardware_profiles = []
    # Follow the deltacloud convention of having numeric ids for the profiles
    for i in 1..5 do
      profile_name = ""
      hwp = ::Deltacloud::HardwareProfile.new(i.to_s) do
        case i
        when 1
          profile_name = 'm1.tiny'
          cpu 1
          memory 512
        when 2
          profile_name = 'm1.small'
          cpu 1
          memory 2048
        when 3
          profile_name = 'm1.medium'
          cpu 2
          memory 4096
        when 4
          profile_name = 'm1.large'
          cpu 4
          memory 8192
        when 5
          profile_name = 'm1.xlarge'
          cpu 8
          memory 16384
        end
        #storage - not supported 
        #architecture 'x86_64'
      end
      hwp.name = profile_name
      @hardware_profiles << hwp
    end
    filter_hardware_profiles(@hardware_profiles, opts)
  end
  
  # For keeping record of "privately pending" instances.
  # i.e. instances, that have been created, but that still need some initialization work
  # that is done in our thread.
  @@pendingInstances = Hash.new
  @@pendingInstancesMutex = Mutex.new

  def realms(credentials, opts=nil)
     vcloud = new_client(credentials)
     realms = []
     safely do
        org = vcloud.organizations.first
        vdc = org.vdcs.first
        realms = [Realm.new(
            :id => vdc.id,
            :name => vdc.name,
            :state => "available",
            :limit => vdc.vm_quota
         )]
     end
     realms
  end

  def convert_state(state)
    case state
      when "creating"
        "PENDING"
      when "off"
        "STOPPED"
      when "on"
        "RUNNING"
      else
        "PENDING"
    end
  end
  
  # Object Creation Status (vcd_51_api_guide.pdf, p. 311)
  # Applies to vAppTemplate, vApp, Vm, Media
  # TODO: Move to fog
  def convert_creation_status(state)
    case state
      when "-1"
        "Could not be created"
      when "0"
        "PENDING" #"Not resolved"
      when "1"
        "Resolved"
      when "2"
        "Deployed"
      when "3"
        "Suspended"
      when "4"
        "RUNNING" #"Powered on"
      when "5"
        "Waiting for user input"
      when "6"
        "Unknown"
      when "7"
        "Unrecognized"
      when "8"
        "STOPPED" #"Powered off"
      when "9"
        "Inconsisten state"
      when "10"
        "Children do not all have the same status"
      when "11"
        "Upload initiated, OVF descriptor pending"
      when "12"
        "Upload initiated, copying contents"
      when "13"
        "Upload initiated, disk contents pending"
      when "14"
        "Upload has been quarantined"
      when "15"
        "Upload quarantine period has expired"
      else
        "unknown status attribute: " + state.to_S
    end
  end

  def instances(credentials, opts=nil)
      instances = []
      vcloud = new_client(credentials)
      safely do
        org = vcloud.organizations.first
        vdc = org.vdcs.first
        vdc.vapps.each do |vapp|
          vm = vapp.vms.first
          if !vm
            status = "PENDING"
          else
            status = convert_state(vm.status)
          end
          
          # Find out if we have own unfinished initialization for the instance ongoing in thread (even if status would be STOPPED)
          @@pendingInstancesMutex.synchronize {
            if @@pendingInstances[vapp.id]
              Fog::Logger.warning("Vapp " + vapp.id + " is pending due to initialization thread.")
              status = "PENDING";
            end
          }
          # Find out profile based on cpu and memory.
          profile_name = "default"
          if status != "PENDING" then
            profiles = hardware_profiles(credentials)
            profiles = profiles.select { |hwp| hwp.include?(:cpu, vm.cpu) }
            profiles = profiles.select { |hwp| hwp.include?(:memory, vm.memory) }
            if profiles.first
              profile_name = profiles.first.id.to_s
            end
          end
          
          profile = InstanceProfile.new(profile_name)
          if status != "PENDING" then
            profile.cpu = vm.cpu
            profile.memory = vm.memory
            disks = vm.hard_disks
            total_storage = 0
            # TODO: Why disks are not always loaded? vm.reload does not help
            if disks.instance_of?(Array) then
              total_storage = disks.inject(0) {|s, i| s + i.values.reduce(:+)}
            end  
            profile.storage = total_storage / 1024
          end
          private_addresses = []
          if vm then
            private_addresses = [InstanceAddress.new(vm.ip_address, :type => :ipv4)]
          end
          inst = Instance.new(
            :id => vapp.id,
            :name => vapp.name,
            :state => status,
            :private_addresses => private_addresses,
            :instance_profile => profile
          )
          inst.actions = instance_actions_for(inst.state)
          instances << inst
        end
      end
      instances = filter_on( instances, :id, opts )
      instances
  end
	
  def images(credentials, opts=nil)
      images = []
      vcloud = new_client(credentials)
      cat = vcloud.organizations.first.catalogs.first
      cat.catalog_items.each do |item|
        vapp_template_id = item.vapp_template_id
        vapp_template = vcloud.get_vapp_template(vapp_template_id)
        images << Image.new(
            :id => vapp_template_id,
            :name => item.name,
            :state => convert_creation_status(vapp_template.body[:status]),
            :architecture => "",
            :hardware_profiles => hardware_profiles(nil),
            :description => item.name
        )
        Fog::Logger.warning "Image. vappt=" + item.id
      end
      images = filter_on( images, :id, opts )
      images
  end

  define_instance_states do
    start.to(:pending)            .on( :create )
    pending.to(:stopped)          .automatically
    stopped.to(:running)          .on( :start )
    running.to(:running)          .on( :reboot )
    running.to(:stopping)         .on( :stop )
    stopping.to(:stopped)         .automatically
    stopped.to(:finish)           .on( :destroy )
   end

  def create_instance(credentials, image_id, opts)
    # Parse hardware profile opts
    cpu_value = 0
    memory_value = 0
    if opts["hwp_id"] && opts[:hwp_id].length>0
      hwp_id = opts[:hwp_id]
      if hwp = hardware_profiles(credentials, {:id => hwp_id}).first
        # Pick the values from the specified hardware profile
        cpu_value = hwp.property("cpu").to_s.to_i
        memory_value = hwp.property("memory").to_s.to_i
      else
        raise "Invalid argument hwp_id=" + hwp_id + ". No such hardware profile."
      end
    end
    if cpu_value == 0 or memory_value == 0
      default_hwp = hardware_profiles(credentials).first # Just take the first profile
      cpu_value    = default_hwp.property("cpu").to_s.to_i
      memory_value = default_hwp.property("memory").to_s.to_i
    end
    # Do not support these, because they would allow to set values that don't match any profile
    #if opts["hwp_cpu"] && opts[:hwp_cpu].length>0
    #  # Take the cpu value from argument
    #  cpu_value = opts["hwp_cpu"].to_i
    #end
    #if opts["hwp_memory"] && opts[:hwp_memory].length>0
    #  # Take the memory value from argument
    #  memory_value = opts["hwp_memory"].to_i
    #end
    
    #Get key opt
    script = ""
    if opts["key"] && opts[:key].length>0
      script = "#!/bin/sh\n\nTUSER=dace\nLOG=/root/vmware-customization-script.log\nPKEY=\""+opts["key"]+"\"\n\n(\necho \"Started: `date`\"\nsudo -u \"$TUSER\" sh -c \"install -d -m 700 ~/.ssh\"\necho \"$PKEY\" |\n\nsudo -u \"$TUSER\" sh -c \"cat >> ~/.ssh/authorized_keys\"\necho \"Finished: `date`\"\n) >> \"$LOG\" 2>&1\n"
    end
    
    vcloud = new_client(credentials)
    params = {}
    name = (opts[:name] && opts[:name].length>0)? opts[:name] : "server#{Time.now.to_s}"
    network_id = (opts[:network_id] && opts[:network_id].length>0) ?
                          opts[:network_id] : vcloud.organizations.first.networks.first.id
    network_name = vcloud.organizations.first.networks.select { |v| v.id == network_id}.first.name
    vdc_id = vcloud.organizations.first.vdcs.first.id
    resp = vcloud.instantiate_vapp_template(name, image_id, {:network_id => network_id, :vdc_id => vdc_id})
    # return Instance object
    inst = Instance.new(
            :id => resp.body[:href].split('/').last,
            :name => resp.body[:name],
            :state => convert_creation_status(resp.body[:status]),
            :instance_profile => InstanceProfile.new("default")
          )
    
    #wait until vm creation completes in a separate thread, otherwise setting cpu or memory would fail
    if cpu_value >= 1 or memory_value >= 1 or script != "" or network_name != ""
      @@pendingInstancesMutex.synchronize {
        @@pendingInstances[inst.id] = true
      }
      Thread.new {
        success = false
        60.times { # wait at most 60 seconds
          Fog::Logger.warning("Waiting on a thread for vm to be created...")
          sleep(1)
          vapp = vcloud.organizations.first.vdcs.first.vapps.select { |v| v.id == inst.id }[0]
          if vapp
            vm = vapp.vms.first
            if vm
              Fog::Logger.warning("VM has been created, finalize it.")
              # Now we have vm created, and can set values
              if cpu_value >= 0
                Fog::Logger.warning("Set CPU value.")
                vm.cpu = cpu_value
              end
              if memory_value >= 1
                Fog::Logger.warning("Set memory value.")
                vm.memory = memory_value
              end
              if script != ""
                Fog::Logger.warning("Set customization script.")
                customization = vm.customization
                customization.enabled = true
                customization.script = script
                customization.has_customization_script = true
                customization.save
              end
              if network_name != ""
                Fog::Logger.warning("Set network: " + network_name)
                network = vm.network
                network.network = network_name
                network.ip_address_allocation_mode="POOL"
                network.save
              end
              success = true
              break
            end
          end
        }
        
        if success
          success = false
          20.times { # wait at most 20 seconds
            Fog::Logger.warning("Waiting on a thread for vm to be ready to be started...")
            sleep(1)
            vapp = vcloud.organizations.first.vdcs.first.vapps.select { |v| v.id == inst.id }[0]
            if vapp
              vm = vapp.vms.first
              if convert_state(vm.status) == "RUNNING"
                # vCloud vms don't currently go to running state automatically, but just in case..
                success = true
                break
              end
              if convert_state(vm.status) == "STOPPED"
                Fog::Logger.warning("VM is ready, start it.")
                vm.power_on
                success = true
                break
              end
            end
          }
        end
        
        @@pendingInstancesMutex.synchronize {
          @@pendingInstances.delete(inst.id)
        }
        if !success
          raise "Error: Could not configure or start VM."
        end
      }
    end
    
    inst.actions = instance_actions_for(inst.state)
    inst
  end

  def reboot_instance(credentials, id)
    #get_vapp(credentials, id).rebootl
  end

  def start_instance(credentials, id)
    Fog::Logger.warning "start instance. vapp_id=" + id
    get_vapp(credentials, id).power_on
  end

  def stop_instance(credentials, id)
    get_vapp(credentials, id).power_off
    vcloud = new_client(credentials)
    Thread.new {
      success = false
      60.times { # wait at most 60 seconds
        Fog::Logger.warning("Waiting on a thread for vm to be stopped...")
        sleep(1)
        vapp = vcloud.organizations.first.vdcs.first.vapps.select { |v| v.id == id }[0]
        if vapp
          vm = vapp.vms.first
          if convert_state(vm.status) == "STOPPED"
            Fog::Logger.warning("VM is stopped, destroy it.")
            if vapp.deployed then
              vapp.undeploy
            end
            vapp.reload
            vapp.destroy()
            success = true
            break
          end
        end
      }
      if !success
        raise "Error: Could not destory VM."
      end
    }
  end

  def destroy_instance(credentials, id)
    vcloud = new_client(credentials)
    vapp = vcloud.organizations.first.vdcs.first.vapps.select { |v| v.id == id }[0]
    if vapp.deployed then
      vapp.undeploy
    end    
    vapp.reload
    Fog::Logger.warning("Delete vapp: " + vapp.id)
    vapp.destroy()
  end

  #alias_method :stop_instance, :destroy_instance
  
  def addresses(credentials, opts={})
    vcloud = new_client(credentials)
    [] 
  end

 private
  def get_vapp(credentials, vapp_id)
    vcloud = new_client(credentials)
    vcloud.organizations.first.vdcs.first.vapps.select { |v| v.id == vapp_id }[0]
  end

 private
  def new_client(credentials)
    Fog::Logger.warning credentials
    connection = Fog::Compute::VcloudDirector.new(
      :vcloud_director_username => credentials.user,
      :vcloud_director_password => credentials.password,
      :vcloud_director_host => api_provider,
      :connection_options => {
        :ssl_verify_peer => false,
        :omit_default_port => true
      }
    )
    Fog::Logger.warning connection
    connection
  end
  
  exceptions do
    on /AuthFailure/ do
      status 401
    end
  end
  
end
    end
  end
end
