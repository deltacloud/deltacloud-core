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

class CIMI::Service::SystemNetworkPort < CIMI::Service::Base

  def self.find(system_id, context, id=:all)
    if id == :all
      ports = context.driver.system_network_ports(context.credentials, {:env=>context, :system_id=>system_id})
      ports.collect {|e| CIMI::Service::SystemNetworkPort.new(context, :model => e)}
    else
      ports = context.driver.system_network_ports(context.credentials, {:env=>context, :system_id=>system_id, :id=>id})
      raise CIMI::Model::NotFound if ports.empty?
      CIMI::Service::SystemNetworkPort.new(context, :model => ports.first)
    end
  end

  def self.collection_for_system(system_id, context)
    system_network_ports = self.find(system_id, context)
    network_ports_url = context.system_network_ports_url(system_id) if context.driver.has_capability? :add_network_ports_to_system
    CIMI::Model::SystemNetworkPort.list(network_ports_url, system_network_ports, :add_url => network_ports_url)
  end

end
