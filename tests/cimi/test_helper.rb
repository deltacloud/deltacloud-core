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

require 'rubygems'
require 'require_relative' if RUBY_VERSION < '1.9'
require_relative '../helpers/common.rb'
require 'singleton'

ENV['API_FRONTEND'] = 'cimi'

require_relative '../../server/lib/initialize'
require_relative "../../server/lib/cimi/models"

# Add CIMI specific config stuff
module CIMI
  module Test

    CIMI_NAMESPACE = "http://schemas.dmtf.org/cimi/1"

    class Config

      include Singleton

      def initialize
        @hash = Deltacloud::Test::yaml_config
        @cimi = @hash["cimi"]
        # Pull in settings for driver reported by server, if any
        # Only relevant when running against Deltacloud
        @hash["cimi"].update(@hash[name] || {})
      end

      def cep_url
        @cimi["cep"]
      end

      def base_uri
        xml.xpath("/c:CloudEntryPoint/c:baseURI", ns).text
      end

      def name
        xml.xpath("/c:CloudEntryPoint/c:name", ns).text
      end

      def basic_auth(u = nil, p = nil)
        u ||= @cimi["user"]
        p ||= @cimi["password"]
        "Basic #{Base64.encode64("#{u}:#{p}")}"
      end

      def auth_header
        if @cimi["user"]
          { "Authorization" => basic_auth }
        else
          {}
        end
      end

      def preferred
        @cimi["preferred"] || {}
      end

      def collections
        xml.xpath("/c:CloudEntryPoint/c:*[@href]", ns).map { |c| c.name.to_sym }
      end

      def features
        {}
      end

      def ns
        { "c" => CIMI_NAMESPACE }
      end


      private
      def xml
        unless @xml
          @xml = RestClient.get(cep_url, "Accept" => "application/xml").xml
        end
        @xml
      end
    end

    def self.config
      Config::instance
    end
  end
end

module CIMI::Test::Methods

  module Global

    def api
      CIMI::Test::config
    end

    def cep(params = {})
      get(api.cep_url, params)
    end
    def discover_uri_for(op, collection, operations = nil)
      unless operations
        cep_json = cep(:accept => :json)
        #get the collection operations:
        operations = get(cep_json.json["#{collection}"]["href"], {:accept=> :json}).json["operations"]
      end
      op_regex = Regexp.new(op, Regexp::IGNORECASE) # "add" == /add/i
      op_uri = operations.inject(""){|res,current| res = current["href"] if current["rel"] =~ op_regex; res} unless operations.nil?
      raise "Couldn't discover the #{collection} Collection #{op} URI" if op_uri.nil? || op_uri.empty?
      op_uri
    end

    def discover_uri_for_subcollection(op, resource_id, subcollection)
      subcollection_uri = get(resource_id, {:accept=> :json}).json[subcollection]["href"]
      subcollection_ops = get(subcollection_uri, {:accept=> :json}).json["operations"]
      discover_uri_for(op, "", subcollection_ops)
    end

    def discover_uri_for_rmd(resource_uri, rmd_type, rmd_uri)
      cep_json = cep(:accept => :json)
      rmd_coll = get cep_json.json["resourceMetadata"]["href"], :accept => :json
      #get the collection index:
      collection_index = rmd_coll.json["resourceMetadata"].index {|rmd| rmd["typeUri"] ==  resource_uri}
      unless rmd_coll.json["resourceMetadata"][collection_index][rmd_type].nil?()
        rmd_index = rmd_coll.json["resourceMetadata"][collection_index][rmd_type].index {|rmd| rmd["uri"] == rmd_uri}
      end
      raise "Couldn't discover the #{rmd_uri} URI" unless rmd_index
    end

    def get_a(cep, item)
      if api.preferred[item]
        item_id = cep.json[item.pluralize]["href"] + "/" + api.preferred[item]
      else
        item_id = get(cep.json[item.pluralize]["href"], {:accept=> :json}).json[full_name(item).pluralize][0]["id"]
      end
    end

    def full_name(item)
      if item.include?("Config")
        full_name = item.gsub("Config", "Configuration")
      else
        full_name = item
      end
    end


    def get(path, params = {})
      RestClient.get absolute_url(path), headers(params)
    end

    def post(path, body, params = {})
      log_request(:post, path, :params => params, :body => body)
      resp = RestClient.post absolute_url(path), body, headers(params)
      log_response(:post, path, resp)
      resp
    end

    def delete(path, params={})
      log_request(:delete, path, :params=>params)
      resp  = RestClient.delete absolute_url(path), headers(params)
      log_response(:delete, path, resp)
      resp
    end

    # Find the model class that can process the body of the HTTP response
    # +resp+
    def model_class(resp)
      resource = nil
      ct = resp.content_type
      if ct == "application/json"
        resp.json["resourceURI"].wont_be_nil
        resource = resp.json["resourceURI"].split("/").last
      elsif ct == "application/xml"
        if resp.xml.root.name == "Collection"
          resource = resp.xml.root["resourceURI"].split("/").last
        else
          resource = resp.xml.root.name
        end
      elsif resp.body.nil? || resp.body.size == 0
        raise "Can not construct model from empty body"
      else
        raise "Unexpected content type #{resp.content_type}"
      end
      CIMI::Model::const_get(resource)
    end

    private
    def absolute_url(path)
      if path.start_with?("http")
        path
      elsif path.start_with?("/")
        api.base_uri + path[1, path.size]
      else
        api.base_uri + "#{path}"
      end
    end

    def headers(params)
      headers = api.auth_header
      if params[:accept]
        headers["Accept"] = "application/#{params[:accept]}"
      else
        # @content_type is set by the harness below
        # if it isn't, default to XML
        headers["Accept"] = @content_type || "application/xml"
      end
      if params[:content_type]
        headers["Content-Type"] = "application/#{params[:content_type]}"
      end
      headers
    end

    # Adding logging capability
    def log
      unless @log
        @log = Logger.new(STDOUT)
        if ENV['LOG_LEVEL'].nil?
          @log.level = Logger::WARN
        else
          @log.level = Logger.const_get ENV['LOG_LEVEL']
        end
        @log.datetime_format = "%H:%M:%S"
        RestClient.log = @log if @log.level == Logger::DEBUG
      end
      @log
    end

    def log_request(method, path, opts = {})
      log.debug("#{method.to_s.upcase} #{absolute_url(path)}")
      if opts[:params]
        h = headers(opts[:params])
        h.keys.sort.each { |k| log.debug "  #{k}: #{h[k]}" }
      end
      log.debug opts[:body] if opts[:body]
    end

    def log_response(method, path, resp)
      log.debug "--> #{resp.code} #{resp.headers[:content_type]}"
      resp.headers.keys.each { |k| log.debug "#{k}: /#{resp.headers[k]}/" }
      log.debug resp.body
      log.debug "/#{method.to_s.upcase} #{absolute_url(path)}"
    end

    def poll_state(machine, state)
      while not machine.state.upcase.eql?(state)
        puts state
        puts 'waiting for machine to be: ' + state.to_s()
        sleep(10)
        machine = machine(:refetch => true)
      end
    end

    def machine_stop_start(machine, action, state)
      uri = discover_uri_for(action, "", machine.operations)
      response = post( uri,
            "<Action xmlns=\"http://schemas.dmtf.org/cimi/1\">" +
              "<action> http://http://schemas.dmtf.org/cimi/1/action/" + action + "</action>" +
            "</Action>",
            :accept => :xml, :content_type => :xml)
      response.code.must_equal 202
      poll_state(machine(:refetch => true), state)
      machine(:refetch => true).state.upcase.must_equal state
    end

  end

  module ClassMethods
    def need_collection(name)
      before :each do
        unless api.collections.include?(name.to_sym)
          skip "Server at #{api.cep_url} doesn't support #{name}"
        end
      end
    end

    #convenience method for checking if collection :foo is supported:
    def collection_supported(name)
      api.collections.include?(name.to_sym)
    end


    def need_capability(op, collection)
      before :each do
        begin
          discover_uri_for(op, collection)
        rescue RuntimeError => e
          skip "Server at #{api.cep_url} doesn't support #{op} for #{collection} collection. #{e.message}"
        end
      end
    end

    def need_rmd(resource_uri, rmd_type, rmd_uri)
      before :each do
        begin
          discover_uri_for_rmd(resource_uri, rmd_type, rmd_uri)
        rescue RuntimeError => e
          skip "Server at #{api.cep_url} doesn't support #{rmd_uri}. #{e.message}"
        end
      end
    end

    # Perform basic collection checks; +model_name+ is the name of the
    # method returning the collection model
    def check_collection(model_name)
      it "must have the \"id\" and \"count\" attributes" do
        coll = self.send(model_name)
        coll.count.wont_be_nil
        coll.count.to_i.must_equal coll.entries.size
        coll.id.must_be_uri
      end

      it "must have a valid id and name for each member" do
        self.send(model_name).entries.each do |entry|
          entry.id.must_be_uri
          member = fetch(entry.id)
          member.id.must_equal entry.id
          member.name.must_equal entry.name
        end
      end
    end

    # Cleanup: stop/destroy the resources created for the tests
    def teardown(created_resources, api_basic_auth)
      @@created_resources = created_resources
      puts "CLEANING UP... resources for deletion: #{@@created_resources.inspect}"
      #systems:
      if @@created_resources[:systems]
        @@created_resources[:systems].each do |sys_id|
          sys = get(sys_id, :accept=>:json)
          delete_op = sys.json["operations"].find { |op| op["rel"] =~ /delete$/ }
          if delete_op
              delete_res = RestClient.delete( delete_op["href"],
                  {'Authorization' => api_basic_auth, :accept => :json} )
              @@created_resources[:systems].delete(sys_id)  if (200..207).include? delete_res.code
              @@created_resources.delete(:systems) if @@created_resources[:systems].empty?
          end
        end
      end

      # machines:
      if not @@created_resources[:machines].nil?
        @@created_resources[:machines].each_index do |i|
          machine = get(@@created_resources[:machines][i], :accept => :json)
          unless machine.json["state"].upcase.eql?("STOPPED")
            stop_op = machine.json["operations"].find { |op| op["rel"] =~ /stop$/ }
            stop_res = post( stop_op["href"],
            "<Action xmlns=\"http://schemas.dmtf.org/cimi/1\">" +
            "<action>http://schemas.dmtf.org/cimi/1/action/stop</action>" +
            "</Action>",
            :accept => :xml, :content_type => :xml )

            machine = get(machine.json["id"], :accept => :json)
          end

          cep_json = cep(:accept => :json)
          while (get(cep_json.json["machines"]["href"], {:accept=>:json}).include?(machine.json["id"]) && (not machine.json["state"].upcase.eql?("STOPPED")))
            puts 'waiting for machine to be STOPPED'
            sleep(3)
            unless (not get(cep_json.json["machines"]["href"], {:accept=>:json}).include?(machine.json["id"]))
              machine = get(machine.json["id"], :accept => :json)
            end
          end

          if get(cep_json.json["machines"]["href"], {:accept=>:json}).include?(machine.json["id"])
            delete_op = machine.json["operations"].find { |op| op["rel"] =~ /delete$/ }
            if delete_op
              delete_res = RestClient.delete( delete_op["href"],
                  {'Authorization' => api_basic_auth, :accept => :json} )
              @@created_resources[:machines][i] = nil if (200..207).include? delete_res.code
            end
          else
            @@created_resources[:machines][i] = nil
          end
        end

        @@created_resources[:machines].compact!
        @@created_resources.delete(:machines) if @@created_resources[:machines].empty?
      end

      # machine_image, machine_volumes, other collections
      if (not @@created_resources[:machine_images].nil?) &&
      (not @@created_resources[:volumes].nil?)
        [:machine_images, :volumes, :machine_templates].each do |col|
          @@created_resources[col].each do |k|
            attempts = 0
            begin
              puts "#{k}"
              res = RestClient.delete( "#{k}",
              {'Authorization' => api_basic_auth, :accept => :json} )
              @@created_resources[col].delete(k) if res.code == 200
            rescue Exception => e
              sleep(10)
              attempts += 1
              retry if (attempts <= 5)
            end
          end
          @@created_resources.delete(col) if @@created_resources[col].empty?
        end
      end

      puts "CLEANUP attempt finished... resources looks like: #{@@created_resources.inspect}"
      raise Exception.new("Unable to delete all created resources - please check: #{@@created_resources.inspect}") unless @@created_resources.empty?
    end

    def query_the_cep(collections = [])
      it "should have root collections" do
        cep = self.send(:subject)
        collections.each do |root|
          r = root.underscore.to_sym
          if cep.respond_to?(r)
            log.info( "Testing collection: " + root )
            coll = cep.send(r)
            coll.must_respond_to :href, "#{root} collection"
            unless coll.href.nil?
              coll.href.must_be_uri "#{root} collection"
              model = fetch(coll.href)
              last_response.code.must_equal 200
              if last_response.content_type.eql?("application/json")
                last_response.json["resourceURI"].wont_be_nil
              end
            else
              log.info( root + " is not supported by this provider." )
            end
          end
        end
      end

    end
  end

  def self.included(base)
    base.extend ClassMethods
    base.extend Global
    base.send(:include, Global)
  end
end

# Special spec class for 'behavior' tests that need to be run once
# for XML and once for JSON
class CIMI::Test::Spec < MiniTest::Spec
  include CIMI::Test::Methods

  attr_reader :format, :content_type

  CONTENT_TYPES = { :xml => "application/xml",
    :json => "application/json" }

  def use_format(fmt)
    @format = fmt
    @content_type = CONTENT_TYPES[fmt]
  end

  def fetch(uri)
    resp = retrieve(uri) { |fmt| get(uri, :accept => fmt) }
    parse(resp)
  end

  def self.it desc = "anonymous", opts = {}, &block
    block ||= proc { skip "(no tests defined)" }

    if opts[:only]
      super("#{desc}") do
        use_format(opts[:only])
        instance_eval &block
      end
    else
      CONTENT_TYPES.keys.each do |fmt|
        super("#{desc} [#{fmt}]") do
          use_format(fmt)
          instance_eval &block
        end
      end
    end
  end

  def self.model(name, opts = {}, &block)
    define_method name do |*args|
      @_memoized ||= {}
      @@_cache ||= {}
      if args[0].is_a?(Hash)
        if args[0][:refetch]
          k = "#{name}_#{@format}"
          @_memoized.delete(k)
          @@_cache.delete(k)
        end
      end

      resp = @_memoized.fetch("#{name}_#{@format}") do |k|
        if opts[:cache]
          @_memoized[k] = @@_cache.fetch(k) do |k|
            @@_cache[k] = retrieve(k, &block)
          end
        else
          @_memoized[k] = retrieve(k, &block)
        end
      end
      @@_cache[:last_response] ||= {}
      @@_cache[:last_response][@format] = resp
      parse(resp)
    end
  end

  def last_response
    @@_cache ||= {}
    @@_cache[:last_response] ||= {}
    @@_cache[:last_response][@format]
  end

  def setup
   unless defined? @@created_resources
     # Keep track of what collections were created for deletion after tests:
     @@created_resources = {:machines=>[], :machine_images=>[], :volumes=>[], :machine_templates=>[]}
   end
   @@created_resources
 end

  private

  def parse(response)
    model_class(response).parse(response.body, @content_type)
  end

  def retrieve(k, &block)
    response = instance_exec(@format, &block)
    if response.body && response.body.size > 0
      assert_equal @content_type, response.content_type
      if @format == :xml
        response.xml.namespaces["xmlns"].must_equal CIMI::Test::CIMI_NAMESPACE
      end
    end
    response
  end
end

MiniTest::Spec.register_spec_type(/Behavior$/, CIMI::Test::Spec)
