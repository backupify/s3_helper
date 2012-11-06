module S3
  module S3HelperFactory

    mattr_accessor :endpoint_config
    self.endpoint_config = {}

    def self.new_s3_helper(bucket)
      return S3Helper.new(bucket, self.endpoint_config)
    end

  end
end