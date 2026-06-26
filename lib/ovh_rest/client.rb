# frozen_string_literal: true

module OvhRest
  # Thin client over the OVH REST API. It signs every request with OVH's
  # authentication scheme on top of {https://github.com/lostisland/faraday
  # Faraday} and exposes one method per HTTP verb.
  #
  # @example
  #   ovh = OvhRest::Client.new(
  #     application_key:    "ak",
  #     application_secret: "as",
  #     consumer_key:       "ck",
  #   )
  #   ovh.get("/me")
  #   ovh.post("/sms/sms-xx12345-1/jobs", { "message" => "hi", "receivers" => ["+33..."] })
  class Client
    # Default OVH API endpoint (European datacenter).
    OVH_API     = 'https://eu.api.ovh.com'
    # Default OVH API version.
    API_VERSION = '1.0'

    # Default request timeout, in seconds.
    DEFAULT_TIMEOUT      = 30
    # Default connection-open timeout, in seconds.
    DEFAULT_OPEN_TIMEOUT = 10

    # HTTP statuses worth retrying: OVH rate limiting and transient gateway/
    # server errors. Retries only apply to idempotent verbs (never POST).
    # @api private
    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

    # @api private
    REDACTED = '[REDACTED]'

    # Request headers that carry credentials and must never reach the logs.
    # @api private
    SENSITIVE_HEADERS = %w[X-Ovh-Application X-Ovh-Consumer X-Ovh-Signature].freeze

    # Characters that must be percent-encoded in a URL path. Slashes and the
    # RFC 3986 sub-delimiters OVH relies on (e.g. commas in batch paths) are kept
    # so the signed URL matches the URL Faraday actually sends, byte-for-byte.
    # @api private
    PATH_UNSAFE = %r{[^A-Za-z0-9\-._~!$&'()*+,;=:@/]}

    # @return [String] the endpoint with the API version, e.g. "https://eu.api.ovh.com/1.0"
    attr_reader :api_uri
    # @return [String] the configured endpoint, e.g. "https://eu.api.ovh.com"
    attr_reader :api_url
    # @return [String] the configured API version, e.g. "1.0"
    attr_reader :api_version

    # @param application_key [String] OVH application key
    # @param application_secret [String] OVH application secret (used to sign requests)
    # @param consumer_key [String] OVH consumer key (may be nil when only calling {#request_consumer_key})
    # @param api_url [String] API endpoint (eu/ca/us)
    # @param api_version [String] API version
    # @param logger [Logger, nil] a Faraday-compatible logger; credential headers are redacted
    # @param timeout [Integer] request timeout in seconds
    # @param open_timeout [Integer] connection-open timeout in seconds
    # @param time_delta [Integer] offset added to the local clock when signing
    # @param auto_sync_time [Boolean] sync the clock against OVH once before the first signed request
    # @param retries [Integer] retry idempotent requests on 429/5xx this many times (0 disables)
    # @param client [Faraday::Connection, nil] inject a pre-built connection (mainly for tests)
    # rubocop:disable Metrics/ParameterLists
    def initialize(application_key:, application_secret:, consumer_key:, api_url: OVH_API, api_version: API_VERSION, logger: nil, timeout: DEFAULT_TIMEOUT, open_timeout: DEFAULT_OPEN_TIMEOUT, time_delta: 0, auto_sync_time: false, retries: 0, client: nil) # rubocop:disable Layout/LineLength
      @api_url            = api_url
      @api_version        = api_version
      @api_uri            = "#{api_url}/#{api_version}"
      @application_key    = application_key
      @application_secret = application_secret
      @consumer_key       = consumer_key
      @logger             = logger
      @timeout            = timeout
      @open_timeout       = open_timeout
      @time_delta         = time_delta
      @auto_sync_time     = auto_sync_time
      @retries            = retries
      @time_synced        = false
      @time_mutex         = Mutex.new
      @client             = client || build_client(@api_uri, @logger)
    end
    # rubocop:enable Metrics/ParameterLists

    # @!method get(path, params = {}, headers: {})
    #   Perform a signed GET request. Params are sent as a query string.
    #   @param path [String] API path, with or without a leading slash
    #   @param params [Hash] query-string parameters
    #   @param headers [Hash] extra request headers (e.g. OVH batch); cannot override the auth headers
    #   @return [Object] the parsed JSON response body
    #   @raise [OvhRest::ApiError] on a 4xx/5xx response
    #   @raise [OvhRest::Error] on a transport failure
    # @!method head(path, params = {}, headers: {})
    #   Perform a signed HEAD request. @see #get
    # @!method delete(path, params = {}, headers: {})
    #   Perform a signed DELETE request. Params are sent as a query string. @see #get
    # @!method post(path, params = {}, headers: {})
    #   Perform a signed POST request. Params are sent as a JSON body.
    #   @param path [String] API path, with or without a leading slash
    #   @param params [Hash] body parameters, serialized to JSON
    #   @param headers [Hash] extra request headers; cannot override the auth headers
    #   @return [Object] the parsed JSON response body
    #   @raise [OvhRest::ApiError] on a 4xx/5xx response
    #   @raise [OvhRest::Error] on a transport failure
    # @!method put(path, params = {}, headers: {})
    #   Perform a signed PUT request. Params are sent as a JSON body. @see #post
    # @!method patch(path, params = {}, headers: {})
    #   Perform a signed PATCH request. Params are sent as a JSON body. @see #post
    %w[get head post put patch delete].each do |verb|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        # frozen_string_literal: true
        def #{verb}(path, params = {}, headers: {})                                     # def get(path, params = {}, headers: {})
          query(method: '#{verb.upcase}', path: path, params: params, headers: headers) #   query(method: 'GET', ...)
        end                                                                             # end
      METHOD
    end

    # Sign and run an arbitrary request. The per-verb helpers ({#get}, {#post}, ...)
    # delegate here; call it directly only for uncommon verbs.
    #
    # @param method [String] HTTP method, e.g. "GET"
    # @param path [String] API path, with or without a leading slash
    # @param params [Hash] query-string params (GET/HEAD/DELETE) or JSON body (POST/PUT/PATCH)
    # @param headers [Hash] extra request headers; cannot override the auth headers
    # @return [Object] the parsed JSON response body
    # @raise [OvhRest::ApiError] on a 4xx/5xx response
    # @raise [OvhRest::Error] on a transport failure
    def query(method:, path:, params: {}, headers: {})
      sync_time_once
      request  = build_request(method, normalize_path(path), params)
      # Caller headers are merged first so the OVH auth headers always win and
      # cannot be clobbered; they are not part of the signature.
      all      = headers.merge(sign(method, request[:signed_url], request[:body]))
      response = @client.run_request(:"#{method.downcase}", request[:request_path], request[:body], all)
      response.body
    rescue Faraday::Error => e
      raise wrap_error(e)
    end

    # Build the signed OVH authentication headers for a request without sending
    # it. Useful for debugging or driving the HTTP layer yourself.
    #
    # @param method [String] HTTP method, e.g. "GET"
    # @param path [String] API path, with or without a leading slash
    # @param params [Hash] query-string params or JSON body, depending on the verb
    # @return [Hash{String=>String}] the X-Ovh-* headers
    def build_headers(method:, path:, params: {})
      request = build_request(method, normalize_path(path), params)
      sign(method, request[:signed_url], request[:body])
    end

    # Start the OVH credential flow: ask for a consumer key scoped to the given
    # access rules. This call is unsigned and only needs the application key; the
    # response carries a consumerKey and a validationUrl the end user must visit
    # to activate it.
    #
    # @param access_rules [Array<Hash>] rules such as `[{ "method" => "GET", "path" => "/*" }]`
    # @param redirection [String, nil] URL to redirect the user to after validation
    # @return [Object] the parsed JSON response (consumerKey, validationUrl, state)
    # @raise [ArgumentError] if access_rules is not a non-empty array of hashes
    # @raise [OvhRest::ApiError] on a 4xx/5xx response
    # @raise [OvhRest::Error] on a transport failure
    def request_consumer_key(access_rules, redirection: nil)
      validate_access_rules!(access_rules)
      payload = { 'accessRules' => access_rules }
      payload['redirection'] = redirection if redirection
      headers  = { 'X-Ovh-Application' => @application_key }
      response = @client.run_request(:post, "/#{@api_version}/auth/credential", payload.to_json, headers)
      response.body
    rescue Faraday::Error => e
      raise wrap_error(e)
    end

    # Fetch the credential currently in use (scope, status, expiration).
    #
    # @return [Object] the parsed JSON response
    # @raise [OvhRest::ApiError] on a 4xx/5xx response
    def current_credential
      get('/auth/currentCredential')
    end

    # Query the (unsigned) OVH /auth/time endpoint and remember the offset
    # between the server clock and the local one. OVH rejects signatures whose
    # timestamp drifts too far, so call this once on a clock-skewed host.
    #
    # @return [Integer] the computed offset, in seconds, between OVH and the local clock
    # @raise [OvhRest::Error] on a transport failure
    def synchronize_time!
      response     = @client.run_request(:get, "/#{@api_version}/auth/time", nil, {})
      @time_delta  = response.body.to_i - Time.now.to_i
      @time_synced = true
      @time_delta
    rescue Faraday::Error => e
      raise wrap_error(e)
    end

    private

    def validate_access_rules!(access_rules)
      return if access_rules.is_a?(Array) && !access_rules.empty? && access_rules.all?(Hash)

      raise ArgumentError, 'access_rules must be a non-empty array of { "method" => ..., "path" => ... } hashes'
    end

    # Lazily synchronize the clock before the first signed request when
    # auto_sync_time was requested, so callers don't have to remember to do it.
    def sync_time_once
      return unless @auto_sync_time && !@time_synced

      # Double-checked under a mutex so concurrent first requests sync only once.
      @time_mutex.synchronize do
        synchronize_time! unless @time_synced
      end
    end

    # Decompose a call into the pieces OVH needs to sign and send.
    # GET/DELETE carry their params in the query string with an empty body;
    # POST/PUT carry a JSON body and no query string. Empty params produce an
    # empty body, matching the OVH signing convention (no body, not "{}").
    def build_request(method, path, params)
      if body_method?(method)
        body  = params.empty? ? '' : params.to_json
        query = nil
      else
        body  = ''
        query = params.empty? ? nil : URI.encode_www_form(params)
      end
      suffix = query ? "?#{query}" : ''
      {
        request_path: "/#{@api_version}/#{path}#{suffix}",
        signed_url:   "#{@api_uri}/#{path}#{suffix}",
        body:         body,
      }
    end

    def body_method?(method)
      %w[POST PUT PATCH].include?(method.to_s.upcase)
    end

    def sign(method, signed_url, body)
      timestamp = compute_timestamp
      {
        'X-Ovh-Application' => @application_key,
        'X-Ovh-Consumer'    => @consumer_key,
        'X-Ovh-Timestamp'   => timestamp,
        'X-Ovh-Signature'   => compute_signature(method, signed_url, body, timestamp),
      }
    end

    def compute_timestamp
      (Time.now.to_i + @time_delta).to_s
    end

    # Translate a Faraday exception into the gem's own error hierarchy so
    # callers never have to rescue Faraday classes directly. Responses carry the
    # OVH error envelope; transport failures (timeouts, DNS) have no response.
    def wrap_error(error)
      response = error.response
      return Error.new(error.message) unless response

      details = response[:body].is_a?(Hash) ? response[:body] : {}
      status  = response[:status]
      error_class_for(status).new(
        details['message'] || error.message,
        status:     status,
        error_code: details['errorCode'],
        http_code:  details['httpCode'],
        response:   response
      )
    end

    def error_class_for(status)
      case status
      when 400..499 then ClientError
      when 500..599 then ServerError
      else ApiError
      end
    end

    def build_client(url, logger)
      Faraday.new(url: url) do |builder|
        builder.options.timeout      = @timeout
        builder.options.open_timeout = @open_timeout
        # raise_error must stay OUTSIDE retry: otherwise it turns a retriable
        # status into an exception before the retry middleware can inspect it.
        builder.response :raise_error
        builder.request :retry, retry_options if @retries.positive?
        builder.request :json
        builder.response :json
        attach_logger(builder, logger) if logger
      end
    end

    # Retry idempotent requests on rate limiting and transient server errors,
    # honoring the Retry-After header with exponential backoff.
    def retry_options
      {
        max:            @retries,
        interval:       0.5,
        backoff_factor: 2,
        retry_statuses: RETRY_STATUSES,
      }
    end

    # Wire Faraday's logger with credential-scrubbing filters so secrets never
    # land in the logs.
    def attach_logger(builder, logger)
      filters = log_filters
      builder.response :logger, logger, headers: true do |fmt|
        filters.each { |regex, replacement| fmt.filter(regex, replacement) }
      end
    end

    # Regex/replacement pairs that scrub credential headers from logged output.
    def log_filters
      SENSITIVE_HEADERS.map do |header|
        [/(#{Regexp.escape(header)}:\s*)[^\r\n]+/i, "\\1#{REDACTED}"]
      end
    end

    # Strip a leading slash (callers may pass paths with or without it) and
    # percent-encode anything that isn't legal in a URL path.
    def normalize_path(path)
      path = path[1..] if path.start_with?('/')
      path.gsub(PATH_UNSAFE) { |char| char.bytes.map { |byte| format('%%%02X', byte) }.join }
    end

    # SHA1 is mandated by the OVH signing protocol (the "$1$" prefix), it is not
    # a security choice on our side; do not "upgrade" it.
    def compute_signature(method, url, body, timestamp)
      "$1$#{Digest::SHA1.hexdigest("#{@application_secret}+#{@consumer_key}+#{method}+#{url}+#{body}+#{timestamp}")}"
    end
  end
end
