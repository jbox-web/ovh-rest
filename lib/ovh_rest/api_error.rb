# frozen_string_literal: true

module OvhRest
  # Raised when the OVH API answers with a 4xx/5xx status. Exposes the parsed
  # OVH error envelope ({ "message", "errorCode", "httpCode" }) and the raw
  # Faraday response hash for callers that need more context.
  #
  # @see OvhRest::ClientError 4xx responses
  # @see OvhRest::ServerError 5xx responses
  class ApiError < Error
    # @return [Integer, nil] HTTP status code, e.g. 403
    attr_reader :status
    # @return [String, nil] OVH "errorCode", e.g. "INVALID_CREDENTIAL"
    attr_reader :error_code
    # @return [String, nil] OVH "httpCode", e.g. "403 Forbidden"
    attr_reader :http_code
    # @return [Hash, nil] the raw Faraday response hash
    attr_reader :response

    # @param message [String] human-readable error message
    # @param status [Integer, nil] HTTP status code
    # @param error_code [String, nil] OVH error code
    # @param http_code [String, nil] OVH HTTP code label
    # @param response [Hash, nil] raw Faraday response hash
    def initialize(message, status: nil, error_code: nil, http_code: nil, response: nil)
      super(message)
      @status     = status
      @error_code = error_code
      @http_code  = http_code
      @response   = response
    end
  end
end
