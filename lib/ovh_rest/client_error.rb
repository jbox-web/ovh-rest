# frozen_string_literal: true

module OvhRest
  # Raised when the OVH API answers with a 4xx status (bad request, invalid
  # credentials, not found, rate limited, ...).
  class ClientError < ApiError
  end
end
