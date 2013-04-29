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

require 'rubygems'
require 'rexml/document'
require 'uri'

require_relative './cloud_client'


module OCCIClient

  #####################################################################
  #  Client Library to interface with the OpenNebula OCCI Service
  #####################################################################
  class Client

    attr_accessor :endpoint

    ######################################################################
    # Initialize client library
    ######################################################################
    def initialize(endpoint_str=nil, user=nil, pass=nil,
             timeout=nil, debug_flag=true)
      @debug   = debug_flag
      @timeout = timeout

      # Server location
      @endpoint = ENV["OCCI_URL"] || endpoint_str || Proc.new(raise "No OpenNebula Provider location configured! Client needs to set \'X-Deltacloud-Provider\' HTTP request header, OR, Deltacloud server administrator must set either the OCCI_URL or API_PROVIDER environment variables")
#"http://localhost:4567"

      # Autentication
      if user && pass
        @occiauth = [user, pass]
      else
        @occiauth = CloudClient::get_one_auth
      end

      if !@occiauth
        raise "No authorization data present"
      end

      @occiauth[1] = Digest::SHA1.hexdigest(@occiauth[1])
    end

    #################################
    # Pool Resource Request Methods #
    #################################

    def get_root
      get('/')
    end

    ######################################################################
    # Retieves the available Instance types
    ######################################################################
    def get_instance_types
      get('/instance_type?verbose=yes')
    end

    ######################################################################
    # Post a new VM to the VM Pool
    # :xmlfile
    ######################################################################
    def post_vms(xmlfile)
      post('/compute', xmlfile)
    end

    ######################################################################
    # Retieves the pool of Virtual Machines
    ######################################################################
    def get_vms(verbose=false)
      get('/compute', verbose)
    end

    ######################################################################
    # Post a new Network to the VN Pool
    # :xmlfile xml description of the Virtual Network
    ######################################################################
    def post_network(xmlfile)
      post('/network', xmlfile)
    end

    ######################################################################
    # Retieves the pool of Virtual Networks
    ######################################################################
    def get_networks
      get('/network')
    end

    ######################################################################
    # Post a new Image to the Image Pool
    # :xmlfile
    ######################################################################
    def post_image(xmlfile, curb=true)
      xml        = File.read(xmlfile)

      begin
        image_info = REXML::Document.new(xml).root
      rescue Exception => e
        error = CloudClient::Error.new(e.message)
        return error
      end

      if image_info.elements['URL']
        file_path = image_info.elements['URL'].text

        m = file_path.match(/^\w+:\/\/(.*)$/)

        if m
          file_path="/"+m[1]
        end
      elsif !image_info.elements['TYPE'] == "DATABLOCK"
        return CloudClient::Error.new("Can not find URL")
      end

      if curb
        if !CURL_LOADED
          error_msg = "curb gem not loaded"
          error = CloudClient::Error.new(error_msg)
          return error
        end

        curl=Curl::Easy.new(@endpoint+"/storage")

        curl.http_auth_types     = Curl::CURLAUTH_BASIC
        curl.userpwd             = "#{@occiauth[0]}:#{@occiauth[1]}"
        curl.verbose             = true if @debug
        curl.multipart_form_post = true

        begin
          postfields = Array.new
          postfields << Curl::PostField.content('occixml', xml)

          if file_path
            postfields << Curl::PostField.file('file', file_path)
          end

          curl.http_post(*postfields)
        rescue Exception => e
          return CloudClient::Error.new(e.message)
        end

        return curl.body_str
      else
        if !MULTIPART_LOADED
          error_msg = "multipart-post gem not loaded"
          error = CloudClient::Error.new(error_msg)
          return error
        end

        params=Hash.new

        if file_path
          file=File.open(file_path)
          params["file"]=UploadIO.new(file,
            'application/octet-stream', file_path)
        end

        params['occixml'] = xml

        url = URI.parse(@endpoint+"/storage")

        req = Net::HTTP::Post::Multipart.new(url.path, params)

        req.basic_auth @occiauth[0], @occiauth[1]

        res = CloudClient::http_start(url, @timeout) do |http|
          http.request(req)
        end

        file.close if file_path

        if CloudClient::is_error?(res)
          return res
        else
          return res.body
        end
      end
    end

    ######################################################################
    # Retieves the pool of Images owned by the user
    ######################################################################
    def get_images(verbose=false)
      get('/storage', verbose)
    end


    ####################################
    # Entity Resource Request Methods  #
    ####################################

    ######################################################################
    # :id VM identifier
    ######################################################################
    def get_vm(id)
      get('/compute/'+id.to_s)
    end

    ######################################################################
    # Puts a new Compute representation in order to change its state
    # :xmlfile Compute OCCI xml representation
    ######################################################################
    def put_vm(xmlfile)
      put('/compute/', xmlfile)
    end

    ####################################################################
    # :id Compute identifier
    ####################################################################
    def delete_vm(id)
      delete('/compute/'+id.to_s)
    end

    ######################################################################
    # Retrieves a Virtual Network
    # :id Virtual Network identifier
    ######################################################################
    def get_network(id)
      get('/network/'+id.to_s)
    end

    ######################################################################
    # Puts a new Network representation in order to change its state
    # :xmlfile Network OCCI xml representation
    ######################################################################
    def put_network(xmlfile)
      put('/network/', xmlfile)
    end

    ######################################################################
    # :id VM identifier
    ######################################################################
    def delete_network(id)
      delete('/network/'+id.to_s)
    end

     #######################################################################
    # Retieves an Image
    # :image_uuid Image identifier
    ######################################################################
    def get_image(id)
      get('/storage/'+id.to_s)
    end

    ######################################################################
    # Puts a new Storage representation in order to change its state
    # :xmlfile Storage OCCI xml representation
    ######################################################################
    def put_image(xmlfile)
      put('/storage/', xmlfile)
    end

    ######################################################################
    # :id VM identifier
    ######################################################################
    def delete_image(id)
      delete('/storage/'+id.to_s)
    end

    private

    def get(path, verbose=false)
      url = URI.parse(@endpoint+path)

      params = []
      params << "verbose=true" if verbose
      params << "#{url.query}" if url.query

      path = url.path
      path << "?#{params.join('&')}"

      req = Net::HTTP::Get.new(path)

      do_request(url, req)
    end

    def post(path, xmlfile)
      url = URI.parse(@endpoint+path)
      req = Net::HTTP::Post.new(url.path)

      req.body=File.read(xmlfile)

      do_request(url, req)
    end

    def delete(path, xmlfile)
      url = URI.parse(@endpoint+path)
      req = Net::HTTP::Delete.new(url.path)

      do_request(url, req)
    end

    def put(path, xmlfile)
      xml = File.read(xmlfile)

      # Get ID from XML
      begin
        info = REXML::Document.new(xml).root
      rescue Exception => e
        error = CloudClient::Error.new(e.message)
        return error
      end

      if info.elements['ID'] == nil
        return CloudClient::Error.new("Can not find RESOURCE ID")
      end

      resource_id = info.elements['ID'].text

      url = URI.parse(@endpoint+path + resource_id)
      req = Net::HTTP::Put.new(url.path)

      req.body = xml

      do_request(url, req)
    end

    def do_request(url, req)
      req.basic_auth @occiauth[0], @occiauth[1]

      res = CloudClient::http_start(url, @timeout) do |http|
        http.request(req)
      end

      if CloudClient::is_error?(res)
        return res
      else
        return res.body
      end
    end
  end
end
