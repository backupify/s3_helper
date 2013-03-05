module S3
  # Wrapper for convinient work with an S3 object.
  class S3Object < Struct.new(:bucket, :path, :filename)

    def s3_helper
      @s3_helper ||= S3::S3HelperFactory.new_s3_helper(bucket)
    end

    def authenticated_url
      s3_helper.authenticated_url(path, filename)
    end

    def store(data)
      s3_helper.store(path, filename, data)
    end

    def delete
      s3_helper.delete(path, filename)
    end

    def fetch
      s3_helper.fetch(path, filename)
    end

    def head
      s3_helper.head(path, filename)
    end

    def rename
      s3_helper.rename(path, filename)
    end
  end
end
