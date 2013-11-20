# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.  The
# ASF licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations
# under the License.
#
# This driver uses the fog library (Geemus - Wesley Beary) to talk to vcloud director... see
# http://github.com/geemus/fog

#
# 17 Jan 2014

require 'fog'
require 'excon'
require 'nokogiri'

module Deltacloud
  module Drivers
    module Vcloud

class VcloudDriver < Deltacloud::BaseDriver
  feature :instances, :user_name do
    { :max_length => 50 }
  end


  define_hardware_profile 'default' do
    cpu   [1,2,4,8]
    memory  [512, 1024, 2048, 4096, 8192]
    storage (1..500).to_a
  end


  def images(credentials, opts=nil)

      image_list = []
      vcloud_client = new_client(credentials)
      profiles = hardware_profiles(nil)

      safely do
        images = vcloud_client.get_execute_query('vAppTemplate').body[:VAppTemplateRecord]
        images.each{ |image|
              image_list << convert_image(image, profiles, credentials.user)
        }
      end
      image_list = filter_on( image_list, :id, opts )
      image_list = filter_on( image_list, :architecture, opts )
      image_list = filter_on( image_list, :owner_id, opts )
      image_list
  end

  def realms(credentials, opts=nil)

    realm_list = []
    vcloud_client = new_client(credentials)

    vdcs = vcloud_client.get_execute_query('orgVdc').body[:OrgVdcRecord]

    if vdcs.class != Array
      vdcs = [vdcs]
    end

    vdcs.each{ |vdc|

      realm = Realm.new( {
        :id => vdc[:href].split('/').last,
        :name=> vdc[:name],
        :state=> "AVAILABLE"
      })

      realm_list << realm
    }

    realm_list = filter_on( realm_list, :id, opts )
    realm_list

  end


  def instances(credentials, opts=nil)

    instances = []
    vcloud_client = new_client(credentials)

    if opts.has_key?(:id) && opts[:id].split('-').first == 'vm'

      vm = vcloud_client.get_vapp(opts[:id]).body
      instances << convert_instance(vm, vcloud_client)

    else

      if opts.has_key?('vapp_id')

        vms = vcloud_client.get_vapp(opts['vapp_id']).body[:Children][:Vm]
        vms.each{|vm|
          instances << convert_instance(vm, vcloud_client)
        }

      else

        vapps = vcloud_client.get_execute_query('vApp').body[:VAppRecord]
        vapps.each{|vapp|
          instances << convert_instance(vapp, vcloud_client)
        }

        vms = vcloud_client.get_execute_query('vm').body[:VMRecord]
        vms.each{|vm|
          instances << convert_instance(vm, vcloud_client)
        }

        instances = filter_on( instances, :id, opts )

      end

    end

    instances

  end

  define_instance_states do
    start.to(:pending)            .on( :create )
    pending.to(:stopped)          .automatically
    pending.to(:finish)           .on( :destroy )
    stopped.to(:running)          .on( :start )
    running.to(:running)          .on( :reboot )
    running.to(:stopping)         .on( :stop )
    stopping.to(:stopped)         .automatically
    stopped.to(:finish)           .on( :destroy )
  end

  def create_instance(credentials, image_id, opts)
    new_vapp = nil
    vapp_opts = {}

    vcloud_client = new_client(credentials)
    name = opts[:name]
    vapp_opts[:network_id] = vcloud_client.get_vdc(opts[:realm_id]).body[:AvailableNetworks][:Network].first[:href].split('/').last
    vapp_opts[:vdc_id] = opts[:realm_id]

    vapp = vcloud_client.instantiate_vapp_template(name, image_id, vapp_opts).body
    vapp_id = vapp[:href].split('/').last
    new_vapp = vcloud_client.get_vapp(vapp_id).body[:VAppRecord]
    return convert_instance(vapp, vcloud_client)

  end

  def reboot_instance(credentials, id)
    safely do
      vcloud_client =  new_client(credentials)
      return vcloud_client.post_reset_vapp(id)
    end
  end

  def start_instance(credentials, id)
    safely do
      vcloud_client =  new_client(credentials)
      return vcloud_client.post_power_on_vapp(id)
    end
  end

  def stop_instance(credentials, id)
    safely do
      vcloud_client = new_client(credentials)
      return vcloud_client.post_undeploy_vapp(id)
    end
  end

  def destroy_instance(credentials, id)
    safely do
      vcloud_client = new_client(credentials)
      return vcloud_client.delete_vapp(id)
    end
  end


#
# PRIVATE METHODS:
#

  private

  def state_map(status)

    case status.to_s
      when '4', 'POWERED_ON'
        'RUNNING'
      when '8', 'POWERED_OFF'
        'STOPPED'
      else
        'PENDING'
    end

  end

  def convert_image(vapp_template, hardware_profiles, account_name)
    Image.new( {
               :id => vapp_template[:href].split('/').last,
               :name => vapp_template[:name],
               :hardware_profiles => hardware_profiles,
               :owner_id => account_name,
               :description => vapp_template[:name]
               })
  end

  def convert_instance(vm, vcloud_client)

    id = vm[:href].split('/').last
    current_state = state_map(vm[:status])
    profile = InstanceProfile.new('default')
    ip_addresses = []


    if vm[:type].nil?

      profile.cpu = vm[:numberOfCpus]
      profile.memory = vm[:memoryAllocationMB]
      profile.storage = vm[:storageKB].to_i / 1024 * 1204

    elsif vm[:type] == 'application/vnd.vmware.vcloud.vm+xml'

      network_selection = vm[:NetworkConnectionSection]

      if network_selection.class == Hash

        network_connections = network_selection[:NetworkConnection]

        if network_connections.class != Array
          network_connections = [network_connections]
        end

        network_connections.each{|network_connection|
          ip_addresses.push(InstanceAddress.new(network_connection[:IpAddress]))
        }

      end

      hardware_selection = vm[:'ovf:VirtualHardwareSection']

      if hardware_selection.class == Hash

        hardware = hardware_selection[:'ovf:Item']

        hardware.each{|hardware_item|

          hardware_item_type = hardware_item.has_key?(:ns12_href) ?  hardware_item[:ns12_href].split('/').last : nil

          if hardware_item_type == 'cpu'
            profile.cpu = hardware_item[:'rasd:VirtualQuantity']
          elsif hardware_item_type == 'memory'
            profile.memory = hardware_item[:'rasd:VirtualQuantity']
          end
          if hardware_item[:'rasd:HostResource'].class == Hash && hardware_item[:'rasd:HostResource'].has_key?(:ns12_capacity) && profile.storage.nil?
            disk = hardware_item[:'rasd:HostResource'][:ns12_capacity]
            profile.storage = disk.to_i / 1024
          end
        }

      end

    end

    Instance.new( {
                 :id => id,
                 :owner_id => vm.has_key?(:ownerName) ? vm[:ownerName] : nil,
                 :name => vm[:name],
                 :state => current_state,
                 :actions => instance_actions_for(current_state),
                 :public_addresses => ip_addresses,
                 :private_addresses => ip_addresses,
                 :instance_profile => profile
                } )

  end

  def new_client(credentials, try = 0)

    Excon.defaults[:ssl_verify_peer] = false

    vcloud_client = nil
    vcloud_token = nil

    safely do
      vcloud_client = Fog::Compute::VcloudDirector.new(
          :vcloud_director_username => "#{credentials.user}",
          :vcloud_director_password => "#{credentials.password}",
          :vcloud_director_host => Deltacloud::Drivers::driver_config[:vcloud][:entrypoint],
          :vcloud_director_show_progress => false
      )

      begin
        user = vcloud_client.vcloud_token
      rescue
        if vcloud_token.nil? && try >= 3
          raise "AuthFailure"
        else
          try = try + 1
          vcloud_client = new_client(credentials, try)
        end
      end

    end
    vcloud_client
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

