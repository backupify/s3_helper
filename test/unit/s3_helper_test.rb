require File.expand_path(File.dirname(__FILE__) + '/../helper.rb')
require 'ostruct'
require 'fog'
require 'active_support/core_ext/numeric'
require 'tempfile'

class S3HelperTest < Test::Unit::TestCase
  setup do
    Fog.mock!

    @connection = Fog::Storage.new(:provider => 'AWS', :aws_access_key_id => 'key', :aws_secret_access_key => 'secret')
    @connection.put_bucket('bucket')
    @connection.put_bucket_versioning('bucket', 'Enabled')

    @helper = S3::S3Helper.new('bucket', {:aws_access_key_id => 'key', :aws_secret_access_key => 'secret'})
  end

  teardown do
    Fog::Mock.reset
  end

  should "require a bucket" do
    assert_raise(S3::BlankBucketException) { S3::S3Helper.new(nil) }
  end

  should "connect on creation" do
    assert !@helper.directory.nil?
  end

  context 'storing a file' do
    should 'require a filename' do
      assert_raise(S3::BlankFileNameException) { @helper.store("path", nil, "data") }
    end

    should "store a file without a path" do
      @helper.store(nil, "filename", "data")

      assert_equal("data", @connection.get_object('bucket', 'filename').body)
    end

    should "store a file with a path" do
      @helper.store("path", "filename", "data")

      assert_equal("data", @connection.get_object('bucket', 'path/filename').body)
    end

    should "singlepart files under 5 mb" do
      @helper.connection.expects(:initiate_multipart_upload).never
      data = 'a' * (5.megabytes - 1)

      @helper.store(nil, 'filename', data)

      assert_equal data, @connection.get_object('bucket', 'filename').body
    end

    should "multipart files over 5 mb" do
      @helper.expects(:singlepart_store).never
      data = 'a' * (5.megabytes + 1)

      #FIXME: Fog mock for initiate_multipart_upload isn't implemented. Remove mocks when it is
      @helper.connection.expects(:initiate_multipart_upload).returns(OpenStruct.new(:body => {'UploadId' => 'fake-upload-id'}))
      @helper.connection.expects(:upload_part).returns(OpenStruct.new(:headers => {'ETag' => 'fake-etag'}))
      @helper.connection.expects(:complete_multipart_upload)

      io = Tempfile.new('s3-helper-test')
      io.unlink
      io.write(data)
      io.rewind

      @helper.store(nil, 'filename', io)

      #FIXME: proper assertion when Fog mock supports multipart upload
      #assert_equal data, @connection.get_object('bucket', 'filename').body

    end

    should "store empty files" do
      assert_nothing_raised do
        @helper.singlepart_store("path", "emptyfile", StringIO.new(''))
      end

      assert_equal("", @connection.get_object('bucket', 'path/emptyfile').body)

      assert_nothing_raised do
        @helper.multipart_store("path", "emptyfile2", StringIO.new(''))
      end

      assert_equal("", @connection.get_object('bucket', 'path/emptyfile2').body)
    end
  end

  context 'fetching a file' do
    should 'require a filename' do
      assert_raise(S3::BlankFileNameException) { @helper.fetch("path", nil) }
    end

    should "fetch a file without a path" do
      @connection.put_object('bucket', 'filename', 'some data')

      assert_equal('some data', @helper.fetch(nil, "filename"))
    end

    should "fetch a file with a path" do
      @connection.put_object('bucket', 'path/filename', 'some data')

      assert_equal('some data', @helper.fetch("path", "filename"))
    end
  end

  context 'fetching a head of a file' do
    should 'return the s3 headers' do
      @connection.put_object('bucket', 'filename', 'some data')

      expectation = @connection.get_object('bucket', 'filename').headers
      actual = @helper.head_object(nil, 'filename')

      assert_equal expectation, actual
      assert actual.keys.include?("Last-Modified")
    end
  end

  context 'fetching many files' do
    should "fetch files without a prefix" do
      @connection.put_object('bucket', 'path1/file1', 'some data1')
      @connection.put_object('bucket', 'path2/file2', 'some data2')

      files = []
      @helper.walk_tree do |s3_file|
        files << s3_file
      end
      assert_equal 2, files.size
      assert_equal('path1/file1', files[0].key)
      assert_equal('some data1', files[0].body)
      assert_equal('path2/file2', files[1].key)
      assert_equal('some data2', files[1].body)
    end

    should "restrict fetched files to a prefix" do
      @connection.put_object('bucket', 'path1/file1', 'some data1')
      @connection.put_object('bucket', 'path2/file2', 'some data2')

      files = []
      @helper.walk_tree('path1') do |s3_file|
        files << s3_file
      end
      assert_equal 1, files.size
      assert_equal('path1/file1', files[0].key)
      assert_equal('some data1', files[0].body)
    end

  end

  context "batch_directory_listing" do
    setup do
      @connection.put_object('bucket', 'path1/file1', 'some data1')
      @connection.put_object('bucket', 'path2/file2', 'some data2')
      @connection.put_object('bucket', 'path3/file3', 'some data3')
      @connection.put_object('bucket', 'path3/file4', 'some data4')
      @connection.put_object('bucket', 'path3/file5', 'some data5')
    end

    should "returns files" do
      files = @helper.batch_directory_listing(nil)

      assert_equal 5, files.size
      assert_equal('path1/file1', files[0].key)
      assert_equal('some data1', files[0].body)
      assert_equal('path2/file2', files[1].key)
      assert_equal('some data2', files[1].body)
      assert_equal('path3/file3', files[2].key)
      assert_equal('some data3', files[2].body)
      assert_equal('path3/file4', files[3].key)
      assert_equal('some data4', files[3].body)
      assert_equal('path3/file5', files[4].key)
      assert_equal('some data5', files[4].body)
    end

    should "return files for given prefix" do
      files = @helper.batch_directory_listing('path1')

      assert_equal 1, files.size
      assert_equal('path1/file1', files[0].key)
      assert_equal('some data1', files[0].body)
    end

    should "limit the result to the given batch size" do
      files = @helper.batch_directory_listing('path3', 2)

      assert_equal 2, files.size
      assert_equal('path3/file3', files[0].key)
      assert_equal('some data3', files[0].body)
      assert_equal('path3/file4', files[1].key)
      assert_equal('some data4', files[1].body)
    end
  end

  context "batch_directory_versions_listing" do
    setup do
      @connection.put_object('bucket', 'path1/file1', 'some data1')
      @connection.put_object('bucket', 'path1/file1', 'some data2')
      @connection.put_object('bucket', 'path1/file2', 'some data3')
      @connection.put_object('bucket', 'path2/file3', 'some data4')
      @connection.delete_object('bucket', 'path2/file3')
    end

    should "returns versions" do
      versions = @helper.batch_directory_versions_listing(nil)

      assert_equal 5, versions.size
      assert_equal('path1/file1', versions[0].key)
      assert_equal('path1/file1', versions[1].key)
      assert_equal('path1/file2', versions[2].key)
      assert_equal('path2/file3', versions[3].key)
      assert_equal('path2/file3', versions[4].key)
    end

    should "return versions for given prefix" do
      versions = @helper.batch_directory_versions_listing('path1')

      assert_equal 3, versions.size
      assert_equal('path1/file1', versions[0].key)
      assert_equal('path1/file1', versions[1].key)
      assert_equal('path1/file2', versions[2].key)
    end

    should "limit the result to the given batch size" do
      versions = @helper.batch_directory_versions_listing('path1', 2)

      assert_equal 2, versions.size
      assert_equal('path1/file1', versions[0].key)
      assert_equal('path1/file1', versions[1].key)
    end
  end

  should "stream a file" do
    yielded_value = nil
    @connection.put_object('bucket', 'path/filename', 'my chunk')

    @helper.fetch("path", "filename", {}) { |chunk| yielded_value = chunk }

    assert_equal yielded_value, 'my chunk'
  end

  context 'deleting a file' do
    should 'require a filename' do
      assert_raise(S3::BlankFileNameException) { @helper.delete('path', nil) }
    end

    should 'delete a file without a path' do
      @connection.put_object('bucket', 'filename', 'some data')
      assert_equal 1, @connection.get_bucket('bucket').body['Contents'].size
      assert_equal 'filename', @connection.get_bucket('bucket').body['Contents'].first['Key']

      @helper.delete(nil, 'filename')
      assert_equal 0, @connection.get_bucket('bucket').body['Contents'].size
    end

    should 'delete a file with a path' do
      @connection.put_object('bucket', 'path/filename', 'some data')
      assert_equal 1, @connection.get_bucket('bucket').body['Contents'].size
      assert_equal 'path/filename', @connection.get_bucket('bucket').body['Contents'].first['Key']

      @helper.delete('path', 'filename')
      assert_equal 0, @connection.get_bucket('bucket').body['Contents'].size
    end
  end

  context 'rename a file' do
    should 'require a source filename' do
      assert_raise(S3::BlankFileNameException) { @helper.rename('path', nil, 'new_filename') }
    end

    should 'require a destination filename' do
      assert_raise(S3::BlankFileNameException) { @helper.rename('path', 'old_filename', nil) }
    end

    should 'create a new file with contents of the old one' do
      @connection.put_object('bucket', 'path/old_filename', 'some data')

      @helper.rename('path', 'old_filename', 'new_filename')

      assert_equal 'some data', @connection.get_object('bucket', 'path/new_filename').body
    end

    should 'delete the old file after the copy is done' do
      @connection.put_object('bucket', 'path/old_filename', 'some data')

      @helper.rename('path', 'old_filename', 'new_filename')

      assert_raise(Excon::Errors::NotFound) do
        @connection.get_object('bucket', 'path/old_filename')
      end
    end
  end

  context 'generating an authenticated URL' do
    setup do
      now = Time.now
      Time.stubs(:now).returns(now)
    end

    should 'require a filename' do
      assert_raise(S3::BlankFileNameException) { @helper.authenticated_url('path', nil) }
    end

    should 'generate a URL for a filename without a path' do
      @connection.put_object('bucket', 'filename', 'some data')

      assert_equal(@connection.get_object_url('bucket', 'filename', Time.now + 5.minutes).split("?").first, @helper.authenticated_url(nil, 'filename'))
    end

    should 'generate a URL for a filename with a path' do
      @connection.put_object('bucket', 'path/filename', 'some data')

      assert_equal(@connection.get_object_url('bucket', 'path/filename', Time.now + 5.minutes).split("?").first, @helper.authenticated_url('path', 'filename'))
    end

    should "find the URL, even if object is on the second 'page' of objects" do
      # The default page size is 1,000 files, so fill up the first page.
      1000.times { |i| @connection.put_object('bucket', i.to_s, 'blah') }

      # The file we care about is now on the second page.
      @connection.put_object('bucket', 'filename', 'some data')

      assert_equal(@connection.get_object_url('bucket', 'filename', Time.now + 5.minutes).split("?").first, @helper.authenticated_url(nil, 'filename'))
    end
  end

  context 'S3HelperFactory' do
    should 'create a new S3Helper object' do
      helper = S3::S3HelperFactory.new_s3_helper('bucket')

      assert helper.is_a? S3::S3Helper
    end

    should 'accept endpoint configuration' do
      endpoint_config = { :host => 'localhost', :port => 4567, :scheme => "http" }
      S3.endpoint_config = endpoint_config

      assert_equal endpoint_config, S3.endpoint_config
    end

    should 'user configs in S3Helper' do
      endpoint_config = { :host => 'localhost', :port => 4567, :scheme => "http" }
      S3.endpoint_config = endpoint_config

      helper = S3::S3HelperFactory.new_s3_helper('bucket')

      assert_equal helper.options, endpoint_config
    end
  end
end
