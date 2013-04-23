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

class CIMI::Service::SystemTemplate < CIMI::Service::Base

  def self.find(id, context)
    if id == :all
      templates = context.driver.system_templates(context.credentials, {:env=>context})
      templates.collect {|e| CIMI::Service::SystemTemplate.new(context, :model => e)}
    else
      templates = context.driver.system_templates(context.credentials, {:env=>context, :id=>id})
      raise CIMI::Model::NotFound if templates.empty?
      CIMI::Service::SystemTemplate.new(context, :model => templates.first)
    end
  end

  def self.delete!(id, context)
    context.driver.destroy_system_template(context.credentials, id)
  end

end
