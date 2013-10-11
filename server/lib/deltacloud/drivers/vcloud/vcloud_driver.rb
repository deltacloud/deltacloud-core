require 'fog'
#require 'excon'
#require 'nokogiri'

module Deltacloud
  module Drivers
    module Vcloud

class VcloudDriver < Deltacloud::BaseDriver
  feature :instances, :user_name do
    { :max_length => 50 }
  end

  define_hardware_profile('default')

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
          status = convert_state(vm.status)
          profile = InstanceProfile.new("default")
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
          inst = Instance.new(
            :id => vapp.id,
            :name => vapp.name,
            :state => status,
            :private_addresses => [InstanceAddress.new(vm.ip_address, :type => :ipv4)],
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
    vcloud = new_client(credentials)
    params = {}
    name = (opts[:name] && opts[:name].length>0)? opts[:name] : "server#{Time.now.to_s}"
    network_id = (opts[:network_id] && opts[:network_id].length>0) ?
                          opts[:network_id] : vcloud.organizations.first.networks.first.id
    resp = vcloud.instantiate_vapp_template(name, image_id, {:network_id => network_id})
    # return Instance object
    inst = Instance.new(
            :id => resp.body[:href].split('/').last,
            :name => resp.body[:name],
            :state => convert_creation_status(resp.body[:status]),
            :instance_profile => InstanceProfile.new("default")
          )
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
