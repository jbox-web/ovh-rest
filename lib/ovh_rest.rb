# frozen_string_literal: true

require 'faraday'
require 'digest'

require 'zeitwerk'
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/ovh-rest.rb")
loader.setup

module OvhRest
end
