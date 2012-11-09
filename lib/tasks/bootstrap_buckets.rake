desc 'Creates the buckets at the endpoint configured by S3::S3HelperFactory.endpoint_config from constant ::STORAGE_BUCKETS'
task :bootstrap_buckets do
  load File.expand_path(Dir.pwd + "/config/initializers/storage.rb")

  s3 = Fog::Storage.new({:aws_access_key_id => '', :aws_secret_access_key => '', :provider => 'AWS'}.merge(S3::S3HelperFactory.endpoint_config))

  ::STORAGE_BUCKETS.each do |bucket|
    response = s3.put_bucket bucket
    if response.status != 200
      puts "something went wrong creating bucket #{bucket}"
    else
      puts "created bucket '#{bucket}'"
    end
  end
end
