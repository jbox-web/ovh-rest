# frozen_string_literal: true

require_relative 'lib/ovh_rest/version'

Gem::Specification.new do |s|
  s.name        = 'ovh-rest'
  s.version     = OvhRest::VERSION::STRING
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Nicolas Rodriguez']
  s.email       = ['nico@nicoladmin.fr']
  s.homepage    = 'https://github.com/jbox-web/ovh-rest'
  s.summary     = 'OVH Rest client'
  s.description = 'OVH Rest client'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 3.0.0'

  s.files = `git ls-files`.split("\n")

  s.add_dependency 'faraday'
  s.add_dependency 'zeitwerk'
end
