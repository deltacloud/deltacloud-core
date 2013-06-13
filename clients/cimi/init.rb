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

require 'rubygems'
require 'sinatra/base'
require 'rack/accept'
require 'haml'
require 'rest-client'
require 'nokogiri'

$:.unshift File.join('lib')
require 'lazy_auth'
require 'client'
require 'cimi_frontend_helper'
require 'entities'

$:.unshift File.join('..', '..','server', 'lib')
require 'deltacloud/core_ext'

# This is absolutely horrendous, but CIMI::Model::Base triggers
# Database lookups, which require JSON at some point.
# FIXME: split out a real client from the CIMI::Model classes
require 'json/pure'

require 'initializers/mock_initialize'

ENV['API_PRODUCTION'] = '1'
ENV['API_FRONTEND'] = 'cimi'

require 'initializers/dependencies_initialize'
require 'initializers/database_initialize'
require 'cimi/models'
