# frozen_string_literal: true

module OvhRest
  # Base class for every error raised by the gem, so callers can rescue
  # OvhRest::Error without coupling to the underlying HTTP backend (Faraday).
  class Error < StandardError
  end
end
