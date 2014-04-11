#
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
#
# 
# Cloud Client for PACI IaaS
#
############################################################################

require 'rubygems'
require 'uri'
require 'net/http'
require "rexml/document"


begin
  require 'rexml/formatters/pretty'
  REXML_FORMATTERS=true
rescue LoadError
  REXML_FORMATTERS=false
end

begin
  require 'net/http/post/multipart'
  MULTIPART_LOADED=true
rescue LoadError
  MULTIPART_LOADED=false
end

#########
# The CloudClient module contains general functionality for connection and error management
############################################################################################
module CloudClient

  # #########################################################################
  # Starts an http connection and calls the block provided. SSL flag
  # is set if needed.
  # #########################################################################
  def self.http_start(url, timeout, &block)
    http = Net::HTTP.new(url.host, url.port)

    if timeout
      http.read_timeout = timeout.to_i
    end

    if url.scheme=='https'
      http.use_ssl = true
      http.verify_mode=OpenSSL::SSL::VERIFY_NONE
    end

    begin
      res = http.start do |connection|
        block.call(connection)
      end
    rescue Errno::ECONNREFUSED => e
      str =  "Error connecting to server (#{e.to_s}).\n"
      str << "Server: #{url.host}:#{url.port}"

      return CloudClient::Error.new(str,"503")
    rescue Errno::ETIMEDOUT => e
      str =  "Error timeout connecting to server (#{e.to_s}).\n"
      str << "Server: #{url.host}:#{url.port}"

      return CloudClient::Error.new(str,"504")
    rescue Timeout::Error => e
      str =  "Error timeout while connected to server (#{e.to_s}).\n"
      str << "Server: #{url.host}:#{url.port}"

      return CloudClient::Error.new(str,"504")
    end

    if res.is_a?(Net::HTTPSuccess)
      res
    else
      CloudClient::Error.new(res.body, res.code)
    end
  end

  # #########################################################################
  # The Error Class represents a generic error in the Cloud Client
  # library. It contains a readable representation of the error.
  # #########################################################################
  class Error
    attr_reader :message
    attr_reader :code

    # +message+ a description of the error
    def initialize(message=nil, code="500")
      @message=message
      @code=code
    end

    def to_s()
      @message
    end
  end

  # #########################################################################
  # Returns true if the object returned by a method of the PACI
  # library is an Error
  # #########################################################################
  def self.is_error?(value)
    value.class==CloudClient::Error
  end
end
