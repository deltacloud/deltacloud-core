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

class CIMI::Service::Disk < CIMI::Service::Base

  def self.find(instance, machine_config, context, id=:all)
    if id == :all
      name = instance.id+"_disk_" #assuming one disk for now...

      if machine_config
        mach_config_disks = machine_config.disks
        return mach_config_disks.map do |d|
          self.new(context, :values => {
            :id => context.machine_url(instance.id) + "/disks/#{name}#{d[:capacity]}",
            :name => "#{name}#{d[:capacity]}",
            :description => "Disk for Machine #{instance.id}",
            :created => instance.launch_time.nil? ?
            Time.now.xmlschema : Time.parse(instance.launch_time).xmlschema,
            :capacity => d[:capacity]
          })
        end
      else
        if instance.instance_profile.override? :storage
          capacity = context.to_kibibyte(instance.instance_profile.storage, 'MB')
        else
          hw_profile = context.driver.hardware_profile(
            context.credentials,
            :id => instance.instance_profile.name
          )
          if hw_profile.storage
            capacity = context.to_kibibyte(hw_profile.storage.value, 'MB')
          end
        end

        return [] unless capacity

        [self.new(context, :values => {
          :id => context.machine_url(instance.id)+"/disks/#{name}#{capacity}",
          :name => name + capacity.to_s,
          :description => "Disk for Machine #{instance.id}",
          :created => instance.launch_time.nil? ?
            Time.now.xmlschema : Time.parse(instance.launch_time).xmlschema,
          :capacity => capacity
        })]
      end
    else
    end
  end

  def self.collection_for_instance(instance_id, context)
    instance = context.driver.instance(context.credentials, :id => instance_id)
    disks = find(instance, nil, context)
    CIMI::Model::Machine::DiskCollection.new(
      :id => context.url("/machines/#{instance_id}/disks"),
      :name => 'default',
      :count => disks.size,
      :description => "Disk collection for Machine #{instance_id}",
      :entries => disks
    )
  end


end
