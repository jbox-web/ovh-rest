# frozen_string_literal: true

module OvhRest
  # @return [Gem::Version] the gem version
  def self.gem_version
    Gem::Version.new VERSION::STRING
  end

  # Gem version components.
  module VERSION
    # @api private
    MAJOR = 1
    # @api private
    MINOR = 0
    # @api private
    TINY  = 0
    # @api private
    PRE   = nil

    # @return [String] the dotted version string, e.g. "1.0.0"
    STRING = [MAJOR, MINOR, TINY, PRE].compact.join('.')
  end
end
