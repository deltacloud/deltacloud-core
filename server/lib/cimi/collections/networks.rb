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

module CIMI::Collections
  class Networks < Base

    set :capability, lambda { |m| driver.respond_to? m }

    collection :networks do
      description 'A Network represents an abstraction of a layer 2 broadcast domain'

      generate_show_operation :with_capability => :networks
      generate_index_operation :with_capability => :networks
      generate_delete_operation :with_capability => :destroy_network
      generate_create_operation :with_capability => :create_network


      action :start, :with_capability => :start_network do
        description "Start specific network."
        param :id, :string, :required
        control do
          network = Network.find(params[:id], self)
          report_error(404) unless network
          if current_content_type == :json
            action = Action.from_json(request.body.read)
          else
            action = Action.from_xml(request.body.read)
          end
          network.perform(action, self) do |operation|
            no_content_with_status(202) if operation.success?
            # Handle errors using operation.failure?
          end
        end
      end

      action :stop, :with_capability => :stop_network do
        description "Stop specific network."
        param :id, :string, :required
        control do
          network = Network.find(params[:id], self)
          report_error(404) unless network
          if current_content_type == :json
            action = Action.from_json(request.body.read)
          else
            action = Action.from_xml(request.body.read)
          end
          network.perform(action, self) do |operation|
            no_content_with_status(202) if operation.success?
            # Handle errors using operation.failure?
          end
        end
      end

      action :suspend, :with_capability => :suspend_network do
        description "Suspend specific network."
        param :id, :string, :required
        control do
          network = Network.find(params[:id], self)
          report_error(404) unless network
          if current_content_type == :json
            action = Action.from_json(request.body.read)
          else
            action = Action.from_xml(request.body.read)
          end
          network.perform(action, self) do |operation|
            no_content_with_status(202) if operation.success?
            # Handle errors using operation.failure?
          end
        end
      end

      operation :network_ports, :with_capability => :network_ports do
        description "Retrieve the Network's NetworkPortCollection"
        param :id, :string, :required
        control do
          network_ports = NetworkPort.collection_for_network(params[:id], self)
          respond_to do |format|
            format.json {network_ports.to_json}
            format.xml  {network_ports.to_xml}
          end
        end
      end


    end

  end
end
