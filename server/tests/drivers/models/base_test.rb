require 'rubygems'
require 'require_relative' if RUBY_VERSION < '1.9'

require_relative 'common'

describe Deltacloud::BaseModel do

  before do
    class CustomModel < Deltacloud::BaseModel
      attr_accessor :name
      attr_accessor :custom
    end
    @model = CustomModel.new(:id => 'm1', :name => 'Model1', :custom => '1')
  end

  describe 'initialize' do

    it 'should properly advertise given attributes' do
      @model.must_respond_to :id
      @model.must_respond_to :name
      @model.must_respond_to :custom
      @model.id.must_equal 'm1'
      @model.name.must_equal 'Model1'
      @model.custom.must_equal '1'
    end

    it 'should report all attributes' do
      @model.attributes.must_include :id
      @model.attributes.must_include :name
      @model.attributes.must_include :custom
    end

  end

end
