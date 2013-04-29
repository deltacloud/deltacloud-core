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

module Deltacloud::Helpers

  module Drivers

    # This will make the Driver helpers, like 'driver'
    # accessible on class level
    #
    def Drivers.included(klass)
      klass.extend Deltacloud::Helpers::Drivers
    end

    def driver_symbol
      driver_name.to_sym
    end

    def driver_name
      Thread.current[:driver] ||= Deltacloud.default_frontend.default_driver.to_s
    end

    def provider_name
      Thread.current[:provider] || ENV['API_PROVIDER']
    end

    def driver_class_name
      driver_name.camelize
    end

    def driver_source_name
      File.join('..', 'drivers', driver_name, driver_name + '_driver.rb')
    end

    def driver_class
      m = Deltacloud::Drivers.const_get(driver_class_name)
      m.const_get(driver_class_name + "Driver").new
    end

    def driver
      begin
        driver_class
      rescue NameError => e
        raise "Driver '#{driver_name}' is not available (#{e.message})."
      end
    end

  end

end
