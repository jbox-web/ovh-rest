# frozen_string_literal: true

# require ruby dependencies
require 'digest'
require 'json'
require 'uri'

# require external dependencies
require 'faraday'
require 'faraday/retry'
require 'zeitwerk'

# load zeitwerk
Zeitwerk::Loader.for_gem.tap do |loader|
  loader.ignore("#{__dir__}/ovh-rest.rb")
  loader.setup
end

# Tiny Ruby wrapper around the OVH REST API. See {OvhRest::Client}.
module OvhRest
  # Convenience shortcut for {OvhRest::Client#initialize OvhRest::Client.new}.
  #
  # @return [OvhRest::Client]
  def self.new(...)
    Client.new(...)
  end
end
