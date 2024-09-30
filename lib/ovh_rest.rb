# frozen_string_literal: true

# require ruby dependencies
require 'digest'

# require external dependencies
require 'faraday'
require 'zeitwerk'

# load zeitwerk
Zeitwerk::Loader.for_gem.tap do |loader|
  loader.ignore("#{__dir__}/ovh-rest.rb")
  loader.setup
end

module OvhRest
end
