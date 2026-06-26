# frozen_string_literal: true

module OvhRest
  class Client
    OVH_API     = 'https://eu.api.ovh.com'
    API_VERSION = '1.0'

    DEFAULT_TIMEOUT      = 30
    DEFAULT_OPEN_TIMEOUT = 10

    REDACTED = '[REDACTED]'

    # Request headers that carry credentials and must never reach the logs.
    SENSITIVE_HEADERS = %w[X-Ovh-Application X-Ovh-Consumer X-Ovh-Signature].freeze

    attr_reader :api_uri

    # rubocop:disable Metrics/ParameterLists
    def initialize(application_key:, application_secret:, consumer_key:, api_url: OVH_API, api_version: API_VERSION, logger: nil, timeout: DEFAULT_TIMEOUT, open_timeout: DEFAULT_OPEN_TIMEOUT, time_delta: 0, auto_sync_time: false, client: nil) # rubocop:disable Layout/LineLength
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
      @time_synced        = false
      @client             = client || build_client(@api_uri, @logger)
    end
    # rubocop:enable Metrics/ParameterLists

    %w[get post put patch delete].each do |verb|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        # frozen_string_literal: true
        def #{verb}(path, params = {})                                 # def get(path, params = {})
          query(method: '#{verb.upcase}', path: path, params: params)  #   query(method: 'GET', path: path, params: params)
        end                                                            # end
      METHOD
    end

    def query(method:, path:, params: {})
      sync_time_once
      request  = build_request(method, normalize_path(path), params)
      headers  = sign(method, request[:signed_url], request[:body])
      response = @client.run_request(:"#{method.downcase}", request[:request_path], request[:body], headers)
      response.body
    rescue Faraday::Error => e
      raise wrap_error(e)
    end

    def build_headers(method:, path:, params: {})
      request = build_request(method, normalize_path(path), params)
      sign(method, request[:signed_url], request[:body])
    end

    # Start the OVH credential flow: ask for a consumer key scoped to the given
    # access rules (an array of { "method" => ..., "path" => ... } hashes). This
    # call is unsigned and only needs the application key; the response carries a
    # consumerKey and a validationUrl the end user must visit to activate it.
    def request_consumer_key(access_rules, redirection: nil)
      payload = { 'accessRules' => access_rules }
      payload['redirection'] = redirection if redirection
      headers  = { 'X-Ovh-Application' => @application_key }
      response = @client.run_request(:post, "/#{@api_version}/auth/credential", payload.to_json, headers)
      response.body
    rescue Faraday::Error => e
      raise wrap_error(e)
    end

    # Query the (unsigned) OVH /auth/time endpoint and remember the offset
    # between the server clock and the local one. OVH rejects signatures whose
    # timestamp drifts too far, so call this once on a clock-skewed host.
    def synchronize_time!
      response     = @client.run_request(:get, "/#{@api_version}/auth/time", nil, {})
      @time_delta  = response.body.to_i - Time.now.to_i
      @time_synced = true
      @time_delta
    rescue Faraday::Error => e
      raise wrap_error(e)
    end

    private

    # Lazily synchronize the clock before the first signed request when
    # auto_sync_time was requested, so callers don't have to remember to do it.
    def sync_time_once
      return unless @auto_sync_time && !@time_synced

      synchronize_time!
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
      ApiError.new(
        details['message'] || error.message,
        status:     response[:status],
        error_code: details['errorCode'],
        http_code:  details['httpCode'],
        response:   response
      )
    end

    def build_client(url, logger)
      Faraday.new(url: url) do |builder|
        builder.options.timeout      = @timeout
        builder.options.open_timeout = @open_timeout
        builder.request :json
        builder.response :raise_error
        builder.response :json
        attach_logger(builder, logger) if logger
      end
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

    def normalize_path(path)
      path.start_with?('/') ? path[1..] : path
    end

    def compute_signature(method, url, body, timestamp)
      "$1$#{Digest::SHA1.hexdigest("#{@application_secret}+#{@consumer_key}+#{method}+#{url}+#{body}+#{timestamp}")}"
    end
  end
end
