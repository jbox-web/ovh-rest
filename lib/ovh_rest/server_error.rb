# frozen_string_literal: true

module OvhRest
  # Raised when the OVH API answers with a 5xx status (server-side failure).
  class ServerError < ApiError
  end
end
