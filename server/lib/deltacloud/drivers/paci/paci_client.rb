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
#require "#{Dir.pwd}/cloud_client.rb"
require 'deltacloud/drivers/paci/cloud_client'  


module PACIClient

  #####################################################################
  #  Client Library to interface with the Parallels PACI Service
  #####################################################################
  class Client

    attr_accessor :endpoint

    ######################################################################
    # Initialize PACI library
    ######################################################################
    def initialize(endpoint_str=nil, user=nil, pass=nil,
             timeout=nil, debug_flag=true)
      @debug   = debug_flag
      @timeout = timeout
      
      # endpoint processement
      # LunaCloud's endpoint is either "http://apicontrol.lunacloud.com:4465/paci/v1.0" or "https://apicontrol.lunacloud.com:4463/paci/v1.0"
      if endpoint_str[-1]=='/'
         @endpoint = endpoint_str.gsub(/\/$/, '')
      else
         @endpoint = endpoint_str
      end
     
      if !@endpoint || @endpoint==""
        raise "Endpoint URL not configured! Client needs to set \'X-Deltacloud-Provider\' HTTP request header, or, Deltacloud server administrator must set the API_PROVIDER environment variable"
      end

      # Autentication
      if user && pass
        @auth = [user, pass]
      # include here call for ENV. Variables auth method if necessary (this method needs to be created in cloud_client.rb file) 
      end

      if !@auth
        raise "No authorization data present"
      end
      # lunacloud performs SHA1 on server side, uncomment the following line in case SHA1 hash encryption is needed 
      # @auth[1] = Digest::SHA1.hexdigest(@auth[1])
    end

      
         

	
    #################################
    # Instance Request Methods      #
    #################################

    ######################################################################
    # Retrieve the list of the available Instances
    ######################################################################
    def get_instances()
      get('/ve')
      #get('/ve/?subscription='+subscription_id)
    end
	
    ######################################################################
    # Retrieve the details of an Instance
    ######################################################################
    def get_instance(ve_name)
      get('/ve/'+ve_name.to_s)
    end

    ######################################################################
    # Create a new Instance
    ######################################################################
    def create_instance(xmlfile)
      post('/ve', xmlfile)
    end
	
    ######################################################################
    # Create a new Instance from Image
    ######################################################################
    def create_instance_from_image(ve_name, image_name)
      post('/ve/'+ve_name.to_s+'/from/'+image_name.to_s)
    end

    ######################################################################
    # Delete an Instance
    ######################################################################
    def delete_instance(ve_name)
      delete('/ve/'+ ve_name.to_s)
    end
	

    ######################################################################
    # Start an Instance
    ######################################################################
    def start_instance(ve_name)
      put('/ve/'+ve_name.to_s+'/start')
    end
	

    ######################################################################
    # Stop an Instance
    ######################################################################
    def stop_instance(ve_name)
      put('/ve/'+ve_name.to_s+'/stop')
    end
	 	
	
    #################################
    # Images Request Methods        #
    #################################
	
    ######################################################################
    # Create a new Image from an Instance
    ######################################################################
    def create_image(subscription_id, ve_name, image_name)
      post('/image/'+ve_name.to_s+'/create/'+image_name.to_s)
      #post('/image/'+ve_name+'/'+subscription_id+'/create/'+image_name)
    end

    ######################################################################
    # Retrieve the list of available Images
    ######################################################################
    def get_images()
      get('/image')
    end

    ######################################################################
    # Retrieve the details of a specific Image
    ######################################################################
    def get_image(image_name)
      get('/image/'+image_name)
    end

    ######################################################################
    # Delete a specific Image										     	
    ######################################################################
    def delete_image(image_id)
      delete('/image/'+image_id)
    end

    ######################################################################
    # Retrieve a specific OS Temaplte to create a VM
    ######################################################################
    def get_os_template(template_name)
      get('/template/'+template_name.to_s)
    end
    
    ######################################################################
    # Retrieve the list of available OS Temapltes to create a VM
    ######################################################################
    def get_os_templates()
      get('/template')
    end
	
    #################################
    # Load Balancer Request Methods #
    #################################

    ######################################################################
    # Retrieve the list of available Load Balancers
    ######################################################################
    def get_load_balancers()
      get('/load-balancer')
    end
	
    ######################################################################
    # Retrieve the details of a specific Load Balancer
    ######################################################################
    def get_load_balancer(lb_name)
      get('/load-balancer/'+lb_name.to_s)
    end
	
    #####################################################################
    # Create a Load Balancer
    ######################################################################
    def create_load_balancer(lb_name)
       # post('load-balancer/'+subscription_id+'/create/'+lb_name)
       post('/load-balancer/create/'+lb_name.to_s)
    end
	
    ######################################################################
    # Delete a Load Balancer
    ######################################################################
    def delete_load_balancer(lb_name)
       delete('/load-balancer/'+lb_name.to_s)
    end
	
    ######################################################################
    # Register an Instance to a Load Balancer
    ######################################################################
    def register_instance(lb_name, ve_name)
       post('/load-balancer/'+lb_name.to_s+'/'+ve_name.to_s)
    end
	
    ######################################################################
    # Unregister an Instance from a Load Balancer
    ######################################################################
    def unregister_instance(lb_name, ve_name)
       delete('/load-balancer/'+lb_name.to_s+'/'+ve_name.to_s)
    end
	
	
    private

    def get(path)
      url = URI.parse(@endpoint+path)
      req = Net::HTTP::Get.new(url.path)
      do_request(url, req)
    end

    def post(path, xmlfile=nil)
      url = URI.parse(@endpoint+path)
      req = Net::HTTP::Post.new(url.path)
      if !xmlfile.nil?
        req.body=xmlfile.to_s
        req.content_type= 'application/xml'
      end
      do_request(url, req)
    end

    def delete(path, xmlfile=nil)

      url = URI.parse(@endpoint+path)
      req = Net::HTTP::Delete.new(url.path)
      if !xmlfile.nil?
        req.body=xmlfile.to_s
        req.content_type= 'application/xml'
      end
      do_request(url, req)
    end

    def put(path, xmlfile=nil)
      url = URI.parse(@endpoint+path)
      req = Net::HTTP::Put.new(url.path)
      if !xmlfile.nil?
        req.body=xmlfile.to_s
        req.content_type= 'application/xml'
      end
      do_request(url, req)
    end

    def do_request(url, req)
      req.basic_auth @auth[0], @auth[1]

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
