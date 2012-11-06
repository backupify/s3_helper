desc 'Creates the buckets at the endpoint configured by S3::S3HelperFactory.endpoint_config. Example: rake bootstrap_buckets[test-bucket]'
task :bootstrap_bucket, :bucket do |t, args|

  if args[:bucket].blank? || args[:bucket].nil?
    puts 'Bucket argument cannot be blank!'
    return
  end

  WebMock.allow_net_connect!

  load File.expand_path(pwd + "/config/initializers/storage.rb")

  s3 = Fog::Storage.new({:aws_access_key_id => '', :aws_secret_access_key => '', :provider => 'AWS'}.merge(S3::S3HelperFactory.endpoint_config))

  response = s3.put_bucket args[:bucket]
  if response.status != 200
    puts "something went wrong: #{response.status}"
  end
end
