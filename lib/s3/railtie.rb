require 'rails/railtie'

module S3
  class Railtie < Rails::Railtie

    rake_tasks do
      load File.expand_path(File.dirname(__FILE__) + "/../tasks/bootstrap_buckets.rake")
    end

  end
end