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

require 'deltacloud/drivers/paci/paci_client'
require 'erb'
require 'rexml/document'

module Deltacloud
  module Drivers
    module Paci

class PaciDriver < Deltacloud::BaseDriver

  feature :instances, :user_name
  feature :instances, :authentication_password
  feature :images,    :user_name

  DEFAULT_REGION = 'EU West'	
	
  ########################
  # Hardware Profiles (LunaCloud)
  ###########################################

  define_hardware_profile('PointFive') do
    cpu			1
    memory 		512
    storage 		10
    architecture 	['x86_64','i386']
  end

  define_hardware_profile('One') do
    cpu			1
    memory 		1024
    storage 		50
    architecture 	['x86_64','i386']
  end

  define_hardware_profile('Two') do
    cpu			2
    memory 		2048
    storage 		100
    architecture 	['x86_64','i386']
  end

  define_hardware_profile('Four') do
    cpu			2
    memory 		4096
    storage 		250
    architecture 	['x86_64','i386']
  end

  define_hardware_profile('Eight') do
    cpu			2
    memory 		8192
    storage 		500
    architecture 	['x86_64','i386']
  end

  define_hardware_profile('OneSix') do
    cpu			4
    memory 		16384
    storage 		1000
    architecture 	['x86_64','i386']
  end

  define_hardware_profile 'Custom'

  ########################
  # Realms
  #######################

  (REALMS = [ Realm.new({
                 :id    => 'EU_West',
                 :name  => 'EU_West',
                 :limit => 'Unknown',
                 :state => 'AVAILABLE'
              }),
              Realm.new({
                 :id    => 'EU_Central',
                 :name  => 'EU_Central',
                 :limit => 'Unknown',
                 :state => 'AVAILABLE'
              })
  ]) unless defined?( REALMS )
  
  def realms(credentials, opts={})
    return REALMS if ( opts.nil? )
    results = REALMS
    # results = filter_on( results, :id, opts )
    # results
  end

  ########################
  # Instances
  #######################

  
  # cpu power is always 1600 MHz, default bandwidth  set to 10240 (min value) but it can go to 102400.
  # bandwidth, no-of-public-ip, and no-of-public-ipv6 are static because no deltacloud instance features are available for these parameters.

  # VM XML Template: 
  VE_TEMPLATE = %q{
  <ve>   
    <name><%=ve_name%></name>
    <cpu number="<%=vcpu%>" power="1600"/>
    <ram-size><%=ve_ram%></ram-size>
    <bandwidth>10240</bandwidth>
    <no-of-public-ip>1</no-of-public-ip>
    <no-of-public-ipv6>0</no-of-public-ipv6>
    <ve-disk local="true" size="<%=ve_disk%>"/>
    <platform>
      <template-info name="<%=image_id%>"/>
      <os-info technology="<%=tech%>" type="<%=type%>"/>
    </platform>
    <backup-schedule name="weekly"/>
    <% if opts[:password] %>
    <admin login="root" password="<%=opts[:password]%>"/>
    <% else %>
    <admin login="root" />
    <% end %>
  </ve>
  }

  VE_STATES = {
    "CREATE"                 => "START",
    "CREATION_IN_PROGRESS"   => "PENDING",
    "CREATED"                => "STOPPED",
    "START_IN_PROGRESS"      => "RUNNING",
    "STARTED"                => "RUNNING",
    "STOP_IN_PROGRESS"       => "STOPPING",
    "STOPPED"                => "STOPPED",
    "DELETE_IN_PROGRESS"     => "STOPPING",
    "DELETED"                => "FINISHED"
  }

  define_instance_states do
    start.to(:pending)          .on( :create )
    pending.to(:stopped)        .automatically
    stopped.to(:pending)        .on( :destroy )
    pending.to(:finish)         .automatically
    stopped.to(:running)        .on( :start )
    running.to(:stopping)       .on( :stop )
    stopping.to(:stopped)       .automatically
    #running.to(:stopping)       .on( :destroy )
    #stopping.to(:finish)        .automatically
  end

  
  def instance(credentials, opts={})
    paci_client = new_client(credentials)
    ve_name=opts[:id]
    xml = treat_response(paci_client.get_instance(ve_name))
    convert_instance(xml, credentials)
  end

  def instances(credentials, opts={})
    paci_client = new_client(credentials)
    xml = treat_response(paci_client.get_instances())
    instances = REXML::Document.new(xml).root.elements.map do |d| 
	    convert_instances(d, credentials)
    end
  end

  def create_instance(credentials, image_id, opts={})
    paci_client = new_client(credentials)

    # Processing name
    if opts[:name] && opts[:name].length>0
      ve_name= opts[:name]
    else
      time=Time.now.to_s
      time=time.split('+').first
      time=time.gsub(/\D/,'')
      ve_name= "Server-"+time
    end

    # Mapping OS template info    
    img_xml = treat_response(paci_client.get_os_template(image_id))
    buffer = REXML::Document.new(img_xml.to_s).root.attributes
    tech=buffer['technology']
    type=buffer['osType']
    
    # Mapping Hardware profiles info
    if opts[:hwp_id]=="PointFive"
      vcpu=1
      ve_ram=512
      ve_disk=10
    elsif opts[:hwp_id]=="One"
      vcpu=1
      ve_ram=1024
      ve_disk=50
    elsif opts[:hwp_id]=="Two"
      vcpu=2
      ve_ram=2048
      ve_disk=100
    elsif opts[:hwp_id]=="Four"
      vcpu=2
      ve_ram=4096
      ve_disk=250
    elsif opts[:hwp_id]=="Eight"
      vcpu=2
      ve_ram=8192
      ve_disk=500
    elsif opts[:hwp_id]=="OneSix"
      vcpu=4
      ve_ram=16384
      ve_disk=1000
    else
      vcpu=1
      ve_ram=512
      ve_disk=10
    end
    
    # Building VE POST XML body
    req_xml = ERB.new(VE_TEMPLATE).result(binding)
     
    # Send/Receive (no need for a variable because the returned message is not used by Deltacloud)
    treat_response(paci_client.create_instance(req_xml))
   
    # Show Instance XML (Deltacloud XML)
    instance(credentials, id: ve_name)
  end

  def start_instance(credentials, id)
    paci_client = new_client(credentials)
    treat_response(paci_client.start_instance(id))
    ve_xml = treat_response(paci_client.get_instance(id))
    convert_instance(ve_xml, credentials)
  end

  def stop_instance(credentials, id)
    paci_client = new_client(credentials)
    treat_response(paci_client.stop_instance(id))
    ve_xml = treat_response(paci_client.get_instance(id))
    convert_instance(ve_xml, credentials)
  end

  def destroy_instance(credentials, id)
    paci_client = new_client(credentials)
    treat_response(paci_client.delete_instance(id))	  
    # 204 HTTP code returned
  end
 
  ########################
  # Images 
  #
  # In the current driver version (v1.0) only OS Template images are used. The end user created images are not listed. 
  # 
  ################################################################################################################################################### 

  def image(credentials, opts={})
    paci_client = new_client(credentials)
    xml = treat_response(paci_client.get_os_template(opts[:id]))
    convert_image(xml, credentials)
  end

  def images(credentials, opts={})
    paci_client = new_client(credentials)
    xml = treat_response(paci_client.get_os_templates())
    images = REXML::Document.new(xml).root.elements.map do |d| 
	    convert_image(d, credentials)
    end
  end

  # Since the OS Templates are owned by the cloud provider the user can not delete them.
  #    
  # def destroy_image(credentials, id)
  #   paci_client = new_client(credentials)
  #   treat_response(paci_client.delete_image(id))	  
  # end

  ########################
  # Load Balancers 
  #######################

  def load_balancer(credentials, opts={})
    paci_client = new_client(credentials)
    xml=treat_response(paci_client.get_load_balancer(opts[:id]))
    convert_load_balancer(xml, credentials)
  end

  def load_balancers(credentials, opts={})
    paci_client = new_client(credentials)
    xml=treat_response(paci_client.get_load_balancers())
    load_balancers=REXML::Document.new(xml).root.elements.map do |d| 
	    convert_load_balancers(d, credentials)
    end
  end

  def create_load_balancer(credentials, opts={})
    paci_client = new_client(credentials)
    lb_name= opts['name']
    if lb_name.nil?
      time=Time.now.to_s
      time=time.split('+').first
      time=time.gsub(/\D/,'')
      lb_name= "LB-"+time
    end
    treat_response(paci_client.create_load_balancer(lb_name))
    load_balancer(credentials, id: lb_name )

  end

  def destroy_load_balancer(credentials, id)
    paci_client = new_client(credentials)
    treat_response(paci_client.delete_load_balancer(id))
    # 204 HTTP code returned
  end

  def lb_register_instance(credentials, opts={})
    paci_client = new_client(credentials)
    lb_name= opts[:id]
    instance_name= opts['instance_id']
    treat_response(paci_client.register_instance(lb_name, instance_name))
    load_balancer(credentials, id: lb_name)
  end
  
  def lb_unregister_instance(credentials, opts={})
    paci_client = new_client(credentials)
    lb_name= opts[:id]
    instance_name= opts['instance_id']
    treat_response(paci_client.unregister_instance(lb_name, instance_name))
    load_balancer(credentials, id: lb_name)
  end


  private

  def new_client(credentials)
    PACIClient::Client.new(api_provider, credentials.user, credentials.password)
  end
  
  ########################
  #   Mapping Parameters   
  ########################

  # This method mapps only OS Templates  
  def convert_image(xml, credentials)
     buffer = REXML::Document.new(xml.to_s).root
     if buffer.attributes['active']=="false"
	     default_state = "DISABLED"
     else
	     default_state = "ACTIVE"
     end

     #mapping
     Image.new({

        :id=>buffer.attributes['name'], 
	:name=>buffer.attributes['name'],
	:description=>"OS: "+buffer.elements[2].attributes['value']+", Virtualization type (VM/CT): "+buffer.attributes['technology'],
	:owner_id=>"LunaCloud",
	:state=>default_state,
	:architecture=>buffer.elements[1].attributes['value'],
	:hardware_profiles=>hardware_profiles(nil)
     })
  end

  # Convert PACI VM parameters to Deltacloud
  def convert_instance(xml, credentials)
    buffer = REXML::Document.new(xml.to_s).root.elements
  
    if buffer['cpu'].attributes['number']=="1" && buffer['ram-size'].text=="512" && buffer['ve-disk'].attributes['size']=="10"
      	 instance_profile='PointFive'
    elsif buffer['cpu'].attributes['number']=="1" && buffer['ram-size'].text=="1024"  && buffer['ve-disk'].attributes['size']=="50"
     	 instance_profile='One'
    elsif buffer['cpu'].attributes['number']=="2" && buffer['ram-size'].text=="2048"  && buffer['ve-disk'].attributes['size']=="100"
   	 instance_profile='Two'
    elsif buffer['cpu'].attributes['number']=="2" && buffer['ram-size'].text=="4096"  && buffer['ve-disk'].attributes['size']=="250"
    	 instance_profile='Four'
    elsif buffer['cpu'].attributes['number']=="2" && buffer['ram-size'].text=="8192"  && buffer['ve-disk'].attributes['size']=="500"
    	 instance_profile='Eight'
    elsif buffer['cpu'].attributes['number']=="4" && buffer['ram-size'].text=="16384" && buffer['ve-disk'].attributes['size']=="1000"
         instance_profile='OneSix'
    else
         instance_profile='Custom'
    end
 
    private_ip=[]
    public_ip=[]

    if buffer['network/public-ip']
    	  buffer.each('network/public-ip') { |ip| public_ip << InstanceAddress.new(ip.attributes['address'].split('/').first, :type => :ipv4)}
    end

    if buffer['network/public-ipv6']
  	  buffer.each('network/public-ipv6') { |ip| public_ip << InstanceAddress.new(ip.attributes['address'].split('/').first, :type => :ipv6)}
    end
  
    private_ip << InstanceAddress.new(buffer['network'].attributes['private-ip'].split('/').first, :type => :ipv4)

    Instance.new( {
      :id=>buffer['name'].text,
      :owner_id=>buffer['subscription-id'].text,
      :name=>buffer['name'].text,
      :image_id=>buffer['platform'].elements['template-info'].attributes['name'],
      :instance_profile=>InstanceProfile.new(instance_profile),
      :realm_id=>DEFAULT_REGION,
      :state=>VE_STATES[buffer['state'].text],
      :public_addresses=>public_ip,
      :private_addresses=>private_ip,
      :username=>buffer['admin'].attributes['login'],
      :password=>buffer['admin'].attributes['password'],
      :actions=> instance_actions_for( VE_STATES[buffer['state'].text] ), 
      :storage_volumes=>[], 
      :launch_time=> "Unknown"
    } )

  end
  	
  # hack to provide vm lists with more details (uses the returned vm_list xml to query each vm at a time reusing convert_instance method
  def convert_instances(xml, credentials)
    paci_client = new_client(credentials)
    ve_name=REXML::Document.new(xml.to_s).root.attributes['name']
    vexml=treat_response(paci_client.get_instance(ve_name))
    convert_instance(vexml, credentials)
  end

  ########
  # Mapping Load Balancers
  #######

  def convert_load_balancer(xml, credentials)
     buffer = REXML::Document.new(xml.to_s).root.elements
     addresses=[]
     if buffer['network/public-ip']
        buffer.each('network/public-ip') {|ip| addresses << InstanceAddress.new(ip.attributes['address'].split('/').first, :type=> :ipv4)}
     end

     if buffer['network/public-ipv6']
        buffer.each('network/public-ipv6') {|ip| addresses << InstanceAddress.new(ip.attributes['address'].split('/').first, :type=> :ipv6)}
     end
     
     balancer=LoadBalancer.new({
       :id=> buffer['name'].text,
       :created_at=> "Unknown",
       :public_addresses=> addresses,
       :realms=> REALMS,
     })
     
     balancer.listeners = []

     buffer.each('used-by') do |vm|
	     balancer.add_listener({
	     :protocol => 'HTTP',
	     :load_balancer_port => 'Unknown',
	     :instance_port => 'Unknown'
	     }) 
     end

     balancer.instances = []

     buffer.each('used-by') do |vm|
	     balancer.instances << instance(credentials, id: vm.attributes['ve-name'])
     end
     balancer

  end

  def convert_load_balancers(xml, credentials)
    paci_client = new_client(credentials)
    lb_name=REXML::Document.new(xml.to_s).root.attributes['name']
    lbxml=treat_response(paci_client.get_load_balancer(lb_name))
    convert_load_balancer(lbxml, credentials)
  end

  ########
  # Errors and returned messages process
  #######

  
  # function to process returned messages 
  def treat_response(res)
    safely do
      if CloudClient.is_error?(res)
        raise case res.code
              when "401" then "AuthenticationFailure"
              when "404" then "ObjectNotFound"
              else res.message
              end
      end
    end
    res
  end
  
  # error treatment seen by Deltacloud
  exceptions do
    on /AuthenticationFailure/ do
      status 401
    end

    on /ObjectNotFound/ do
      status 404
    end

    on // do
      status 502
    end
  end
  
end

    end
  end
end
