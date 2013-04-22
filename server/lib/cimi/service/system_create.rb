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

class CIMI::Service::SystemCreate < CIMI::Service::Base

  def create
    if system_template.href?
      template = resolve(system_template)
    else
      # FIXME: What if this href isn't there ? What if the user
      # tries to override some aspect of the system template ?
    end
    params = {
      :system_template => template,
      :name => name,
      :description => description,
      :env => context
    }
    result = context.driver.create_system(context.credentials, params)
    result.name = name if name
    result.description = description if description
    result.property = property if property
#    result.save
    result
  end

end
