# frozen_string_literal: true

module OvhRest
  class Client
    OVH_API = 'https://eu.api.ovh.com'
    VERSION = '1.0'

    attr_reader :api_uri

    # Used in tests to stub Faraday object
    attr_writer :client

    # rubocop:disable Metrics/ParameterLists
    def initialize(application_key:, application_secret:, consumer_key:, api_url: OVH_API, api_version: VERSION, logger: nil)
      @api_url            = api_url
      @api_version        = api_version
      @api_uri            = "#{api_url}/#{api_version}"
      @application_key    = application_key
      @application_secret = application_secret
      @consumer_key       = consumer_key
      @logger             = logger
      @client             = build_client(@api_uri, @logger)
    end
    # rubocop:enable Metrics/ParameterLists

    %w[get post put delete].each do |verb|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        # frozen_string_literal: true
        def #{verb}(path, params = {})                                 # def get(path, params = {})
          query(method: '#{verb.upcase}', path: path, params: params)  #   query(method: 'GET', path: path, params: params)
        end                                                            # end
      METHOD
    end

    def query(method:, path:, params: {})
      path     = normalize_path(path)
      headers  = build_headers(method: method, path: path, params: params)
      response = @client.run_request(:"#{method.downcase}", "/#{@api_version}/#{path}", params.to_json, headers)
      response.body
    end

    def build_headers(method:, path:, params: {})
      path       = normalize_path(path)
      signed_url = "#{@api_uri}/#{path}"
      timestamp  = Time.now.to_i.to_s
      signature  = compute_signature(method, signed_url, params.to_json, timestamp)
      {
        'X-Ovh-Application' => @application_key,
        'X-Ovh-Consumer'    => @consumer_key,
        'X-Ovh-Timestamp'   => timestamp,
        'X-Ovh-Signature'   => signature,
      }
    end

    private

    def build_client(url, logger)
      Faraday.new(url: url) do |builder|
        builder.request :json
        builder.response :raise_error
        builder.response :json
        builder.response :logger, logger if logger
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
