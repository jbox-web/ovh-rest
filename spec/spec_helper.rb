# frozen_string_literal: true

require 'simplecov'
require 'rspec'

# Start SimpleCov
SimpleCov.start do
  add_filter 'spec/'
end

# Load our own config
require_relative 'config_rspec'

require 'ovh-rest'
