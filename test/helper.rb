require 'rubygems'
require 'bundler'

begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require 'test/unit'
require 'shoulda'
require 'mocha'
require 'fog'
require_relative "../lib/s3_helper"

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

class Test::Unit::TestCase

  # This allows you to redefine a constant for a given block.
  # It restores the original value to the constant after the block executes.
  # constant_name should be a string that includes the full path includes all parent classes and modules.
  # for example: "S3::Helper::MAX_KEYS"
  def redefine_constant(constant_name, constant_value)
    constant_class = constant_name.split(/::/)[0..-2].join('::').constantize rescue Object
    constant_variable_name = constant_name.split(/::/).last

    old_value = constant_name.constantize

    constant_class.send(:remove_const, constant_variable_name.to_sym)
    constant_class.send(:const_set, constant_variable_name.to_sym, constant_value)

    if block_given?
      begin
        yield
      ensure
        constant_class.send(:remove_const, constant_variable_name.to_sym)
        constant_class.send(:const_set, constant_variable_name.to_sym, old_value)
      end
    end
  end

end

