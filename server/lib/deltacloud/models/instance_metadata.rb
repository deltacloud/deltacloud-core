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

# Model to store the hardware profile applied to an instance together with
# any instance-specific overrides

module Deltacloud
  class InstanceMetadata
    def initialize(metadata)
      @metadata = metadata
    end

    def [](key)
      @metadata = {} if @metadata.nil?
      @metadata[key]
    end

    def []=(key, value)
      @metadata = {} if @metadata.nil?
      @metadata[key] = value
    end

    def each_pair
      @metadata = {} if @metadata.nil?
      @metadata.each_pair do |k,v|
          yield k, v
      end
    end

    def size
      @metadata = {} if @metadata.nil?
      @metadata.size
    end

    def each
      @metadata = {} if @metadata.nil?
      @metadata.each
    end

    def to_s
      return @metadata.to_s
    end

    def to_json
      return @metadata.to_json
    end

    def to_hash(context=nil)
      return @metadata
    end
  end
end
