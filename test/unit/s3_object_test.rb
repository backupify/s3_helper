require File.expand_path(File.dirname(__FILE__) + '/../helper.rb')
require 'ostruct'
require 'fog'
require 'active_support/core_ext/numeric'
require 'tempfile'

class S3ObjectTest < Test::Unit::TestCase
  setup do
    Fog.mock!

    @connection = Fog::Storage.new(:provider => 'AWS', :aws_access_key_id => 'key', :aws_secret_access_key => 'secret')
    @connection.put_bucket('bucket')
    @connection.put_bucket_versioning('bucket', 'Enabled')

    S3::S3HelperFactory.endpoint_config = {:aws_access_key_id => 'key', :aws_secret_access_key => 'secret'}
    @s3_object = S3::S3Object.new('bucket', 'path', 'filename')
  end

  teardown do
    Fog::Mock.reset
  end

  should "store a file with a path" do
    @s3_object.store("data")

    assert_equal "data", @connection.get_object('bucket', 'path/filename').body
  end

  context 'for a filename with a path' do
    setup do
      @connection.put_object('bucket', 'path/filename', 'some data')
    end

    should 'generate a URL for a filename with a path' do
      assert_equal @connection.get_object_url('bucket', 'path/filename', Time.now + 5.minutes),
                   @s3_object.authenticated_url
    end

    should 'delete a file with a path' do
      @s3_object.delete
      assert_equal 0, @connection.get_bucket('bucket').body['Contents'].size
    end

    should "fetch a file with a path" do
      assert_equal 'some data',
                   @s3_object.fetch
    end
  end
end
