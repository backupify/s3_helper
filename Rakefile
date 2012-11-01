# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "s3_helper"
  gem.homepage = "http://github.com/backupify/s3_helper"
  gem.license = "MIT"
  gem.summary = "This gem abstracts communication with S3"
  gem.description = "This gem abstracts communication with S3"
  gem.email = "andrew@backupify.com"
  gem.authors = ["Andrew Jorgensen"]
  # dependencies defined in Gemfile
end

#Private gem - do not create rubygems.org tasks
#Jeweler::RubygemsDotOrgTasks.new

require 'ci/reporter/rake/test_unit'
require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "twitter-soa-client #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
