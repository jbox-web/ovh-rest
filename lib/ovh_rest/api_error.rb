# frozen_string_literal: true

module OvhRest
  # Raised when the OVH API answers with a 4xx/5xx status. Exposes the parsed
  # OVH error envelope ({ "message", "errorCode", "httpCode" }) and the raw
  # Faraday response hash for callers that need more context.
  class ApiError < Error
    attr_reader :status, :error_code, :http_code, :response

    def initialize(message, status: nil, error_code: nil, http_code: nil, response: nil)
      super(message)
      @status     = status
      @error_code = error_code
      @http_code  = http_code
      @response   = response
    end
  end
end
