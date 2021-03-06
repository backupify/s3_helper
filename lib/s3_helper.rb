require 'open-uri'
require 'excon'
require 'exception_helper'
require 'active_support/core_ext/object/try'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/numeric/time'

require 's3/s3_helper_factory'
require 's3/railtie' if defined?(Rails)
require 's3/s3_object'

module S3
  class BlankBucketException < StandardError; end
  class BlankFileNameException < StandardError; end

  class S3Helper
    include ExceptionHelper::Retry

    RETRYABLE_EXCEPTIONS = [Excon::Errors::Error]
    MAX_KEYS = 1000

    attr_accessor :directory
    attr_reader :options

    # Creates the S3Helper objects
    #
    # @param [String] bucket The bucket that we want to interact with. This does not create the bucket if it does not already exist
    # @param [Hash] options Options that will be passed down to Fog for :provider => AWS. Common options we use are: :aws_access_key_id, :aws_secret_access_key, :host, :port, :scheme
    # @return [S3Helper] the S3Helper object to interact with S3
    def initialize(bucket, options = {})
      raise BlankBucketException.new unless bucket
      @options = options

      connect!(bucket)
    end

    #data can be a string or io handle
    def store(path, filename, data, opts={})
      if data.respond_to?(:read)
        multipart_store(path, filename, data, opts)
      else
        singlepart_store(path, filename, data, opts)
      end
    end

    def singlepart_store(path, filename, data, opts={})
      fullpath = validate_path(path, filename)
      file = nil

      # store the object
      #logger.debug "S3 - Storing object: #{fullpath}"

      retry_on_failure(*RETRYABLE_EXCEPTIONS) do
        file = @directory.files.new(opts.merge(:key => fullpath))
        file.body = data
        file.save
      end

      file
    end

    def multipart_store(path, filename, data, opts={})
      opts = {:chunk_size => (5.megabytes)}.merge(opts)

      chunk = data.read(opts[:chunk_size])

      if chunk.nil? || (chunk.size < opts[:chunk_size])
        singlepart_store(path, filename, chunk, opts)
      else
        fullpath = validate_path(path, filename)
        #logger.info "S3 - Multipart uploading #{fullpath}"

        part_ids = []

        response = @storage.initiate_multipart_upload(@bucket, fullpath, opts)
        begin
          upload_id = response.body['UploadId']

          while chunk
            next_chunk = data.read(opts[:chunk_size])
            if data.eof?
              chunk << next_chunk
              next_chunk = nil
            end
            part_number = part_ids.size + 1
            #logger.info("S3 - Uploading part #{part_number}")
            retry_on_failure(*RETRYABLE_EXCEPTIONS) do
              response = @storage.upload_part(@bucket, fullpath, upload_id, part_number, chunk)
              part_ids << response.headers['ETag']
            end
            chunk = next_chunk
          end

          @storage.complete_multipart_upload(@bucket, fullpath, upload_id, part_ids)
            #logger.info("S3 - Completed multipart upload: #{upload_id}")

        rescue Exception => e
          #logger.error("S3 - Aborting multipart upload: #{upload_id}")
          # don't want abort to fail, so reconnect to make sure fog
          # storage instance not in a funky state
          connect!(@bucket)
          @storage.abort_multipart_upload(@bucket, fullpath, upload_id)
          raise
        end
      end
    end

    def fetch(path, filename, opts={}, &block)
      fullpath = validate_path(path, filename)
      if block_given?
        connection.get_object(@bucket, fullpath, opts, &block)
      else
        begin
          connection.get_object(@bucket, fullpath, opts).body
        rescue Excon::Errors::NotFound
          nil
        end
      end
    end

    alias_method :stream, :fetch

    def head_object(path, filename, opts={})
      fullpath = validate_path(path, filename)

      #logger.debug "S3 - Fetching head of object: " + fullpath
      connection.head_object(@bucket, fullpath, opts).headers
    end

    def head(path, filename, opts={})
      fullpath = validate_path(path, filename)

      @directory.files.head(fullpath, opts)
    end

    def delete(path, filename, opts={})
      fullpath = validate_path(path, filename)

      # store the object
      #logger.debug "S3 - Deleting object: " + fullpath
      retry_on_failure(*RETRYABLE_EXCEPTIONS) do
        @directory.files.get(fullpath, opts).try(:destroy)
      end
    end

    def rename(path, original_filename, new_filename)
      original_file = @directory.files.get(validate_path(path, original_filename))

      connection.copy_object(@directory.key, validate_path(path, original_filename), @directory.key, validate_path(path, new_filename))

      original_file.destroy
    end

    def authenticated_url(path, filename, opts={})
      opts = {:expires_in => 5.minutes}.merge(opts)
      fullpath = validate_path(path, filename)

      # Extract the expiration time from the options.
      expiration_time = opts[:expires].present? ? opts[:expires] : Time.now + opts[:expires_in]
      opts.delete(:expires)
      opts.delete(:expires_in)

      @directory.files.get_https_url(fullpath, expiration_time)
    end

    def connection
      @directory.service
    end

    def key
      @directory.key
    end

    def storage_size(prefix)
      sum = 0
      each_s3_metadata_for_prefix(prefix){ |metadata| sum += metadata['Size'] }
      sum
    end

    # return a hash of filename => file size given an s3 prefix
    def file_sizes_for_prefix(prefix)
      file_sizes_hash = {}
      each_s3_metadata_for_prefix(prefix){ |metadata| file_sizes_hash[metadata['Key']] = metadata['Size'] }
      file_sizes_hash
    end

    def each_s3_metadata_for_prefix(prefix)
      marker = nil

      loop do
        response = @directory.connection.get_bucket(@directory.key, 'prefix' => prefix, 'max-keys' => MAX_KEYS, 'marker' => marker)

        response.body['Contents'].each { |response_body| yield response_body }

        marker = response.body['Contents'].last.try(:[], 'Key')

        # IsTruncated will be false when we've retrieved all the items from S3.
        break unless response.body['IsTruncated']
      end

      nil
    end

    # returns a list no bigger than batch_size of files from s3 in a given directory (with a given prefix).
    # does not currently support any sort of paging; it just returns the first [batch_size] files
    def batch_directory_listing(prefix, batch_size = MAX_KEYS)
      @directory.files.all('prefix' => prefix, 'max-keys' => batch_size)
    end

    def batch_directory_versions_listing(prefix, batch_size = MAX_KEYS)
      @directory.versions.all('prefix' => prefix, 'max-keys' => batch_size)
    end

    def walk_tree(prefix=nil)
      # Grab a new S3 connection since this method destroys the cached copy of files once the prefix is applied.
      s3 = S3Helper.new(@directory.key, @options)

      iter = s3.directory.files
      iter.prefix = prefix if prefix

      iter.each do |s3_file|
        yield s3_file
      end
    end

    protected

    def connect!(bucket)
      @bucket = bucket

      @storage_params = {:provider => 'AWS',
                         :persistent => false,
                         :connection_options => { :retry_limit => 0 }
      }.merge(@options)

      @storage = Fog::Storage.new(@storage_params)

      # This call looks misleading.  What we're doing is creating an in-memory representation of an existing bucket.
      # The bucket :key will be used in operations related to interaction of files within the directory.
      @directory = @storage.directories.new(:key => bucket)
    end

    def validate_path(path, filename)
      raise BlankFileNameException.new unless filename

      fullpath = ""
      fullpath = path + "/" if path.present?
      fullpath = fullpath + filename

      return fullpath
    end

  end
end
