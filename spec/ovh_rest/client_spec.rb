# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OvhRest::Client do
  # Faraday test adapter
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  # Faraday::Connection object that uses the test adapter, mirroring the
  # production middleware stack (json request/response, raise_error).
  let(:conn) do
    Faraday.new(url: OvhRest::Client::OVH_API) do |b|
      b.request :json
      b.response :raise_error
      b.response :json
      b.adapter(:test, stubs)
    end
  end

  # Client with the stubbed connection object injected
  let(:client) { described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz', client: conn) } # rubocop:disable Layout/LineLength

  # Freeze the clock so signatures (which embed a timestamp) are deterministic.
  let(:frozen_time) { 1_700_000_000 }

  before { allow(Time).to receive(:now).and_return(Time.at(frozen_time)) }

  # Clear default connection to prevent it from being cached between different tests.
  # This allows for each test to have its own set of stubs
  after do
    Faraday.default_connection = nil
  end

  # Reference implementation of the OVH signature, used to assert the client
  # signs the exact (method, url, body, timestamp) tuple we expect.
  def signature_for(method:, url:, body:, timestamp: frozen_time.to_s)
    "$1$#{Digest::SHA1.hexdigest("bar+baz+#{method}+#{url}+#{body}+#{timestamp}")}"
  end

  describe '#api_uri' do
    it 'returns ovh api url with version' do
      expect(client.api_uri).to eq 'https://eu.api.ovh.com/1.0'
    end

    it 'exposes the configured endpoint and api version' do
      expect(client.api_url).to eq 'https://eu.api.ovh.com'
      expect(client.api_version).to eq '1.0'
    end

    it 'honors a custom endpoint and api version when signing' do
      ca  = described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz',
                                api_url: 'https://ca.api.ovh.com', api_version: '1.5', client: conn)
      url = 'https://ca.api.ovh.com/1.5/me'

      expect(ca.api_uri).to eq 'https://ca.api.ovh.com/1.5'
      expect(ca.build_headers(method: 'GET', path: '/me')['X-Ovh-Signature'])
        .to eq signature_for(method: 'GET', url: url, body: '')
    end
  end

  describe 'client injection' do
    it 'accepts a Faraday connection via the constructor' do
      injected = described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz',
                                     client: conn)
      stubs.get('https://eu.api.ovh.com/1.0/sms/sms-aa12345-1') do
        [200, { 'Content-Type': 'application/json' }, '{"foo":"bar"}']
      end
      expect(injected.get('/sms/sms-aa12345-1')).to eq({ 'foo' => 'bar' })
    end

    it 'does not expose a public client writer' do
      expect(client).not_to respond_to(:client=)
    end
  end

  describe 'timeouts' do
    let(:bare_client) do
      described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz', **opts)
    end

    let(:built_connection) { bare_client.instance_variable_get(:@client) }

    context 'with defaults' do
      let(:opts) { {} }

      it 'applies a sane default request timeout' do
        expect(built_connection.options.timeout).to eq 30
      end

      it 'applies a sane default open timeout' do
        expect(built_connection.options.open_timeout).to eq 10
      end
    end

    context 'when overridden' do
      let(:opts) { { timeout: 5, open_timeout: 2 } }

      it 'uses the given request timeout' do
        expect(built_connection.options.timeout).to eq 5
      end

      it 'uses the given open timeout' do
        expect(built_connection.options.open_timeout).to eq 2
      end
    end
  end

  describe 'path normalization' do
    it 'treats paths with and without a leading slash identically' do
      with_slash = client.build_headers(method: 'GET', path: '/me')
      without    = client.build_headers(method: 'GET', path: 'me')

      expect(with_slash).to eq(without)
    end

    it 'percent-encodes unsafe path characters while preserving slashes' do
      url     = 'https://eu.api.ovh.com/1.0/sms/foo%20bar/baz'
      headers = client.build_headers(method: 'GET', path: '/sms/foo bar/baz')

      expect(headers['X-Ovh-Signature']).to eq signature_for(method: 'GET', url: url, body: '')
    end

    it 'keeps OVH batch sub-delimiters such as commas unescaped' do
      url     = 'https://eu.api.ovh.com/1.0/dedicated/server/ns1,ns2'
      headers = client.build_headers(method: 'GET', path: '/dedicated/server/ns1,ns2')

      expect(headers['X-Ovh-Signature']).to eq signature_for(method: 'GET', url: url, body: '')
    end
  end

  describe '#build_headers' do
    it 'signs a bodyless GET with an empty body' do
      url     = 'https://eu.api.ovh.com/1.0/sms/sms-aa12345-1'
      headers = client.build_headers(method: 'GET', path: '/sms/sms-aa12345-1')

      expect(headers).to eq({
        'X-Ovh-Application' => 'foo',
        'X-Ovh-Consumer'    => 'baz',
        'X-Ovh-Signature'   => signature_for(method: 'GET', url: url, body: ''),
        'X-Ovh-Timestamp'   => frozen_time.to_s,
      })
    end

    it 'signs the query string for a GET with params' do
      url     = 'https://eu.api.ovh.com/1.0/me/bill?date=2024&foo=bar'
      headers = client.build_headers(method: 'GET', path: '/me/bill', params: { 'date' => '2024', 'foo' => 'bar' })

      expect(headers['X-Ovh-Signature']).to eq signature_for(method: 'GET', url: url, body: '')
    end

    it 'signs the JSON body for a POST' do
      url     = 'https://eu.api.ovh.com/1.0/sms/jobs'
      headers = client.build_headers(method: 'POST', path: '/sms/jobs', params: { 'message' => 'hi' })

      expect(headers['X-Ovh-Signature']).to eq signature_for(method: 'POST', url: url, body: '{"message":"hi"}')
    end
  end

  describe '#query' do
    it 'calls ovh api' do
      stubs.get('https://eu.api.ovh.com/1.0/sms/sms-aa12345-1') do
        [200, { 'Content-Type': 'application/json' }, '{"foo":"bar"}']
      end
      expect(client.query(method: 'GET', path: '/sms/sms-aa12345-1')).to eq({ 'foo' => 'bar' })
      stubs.verify_stubbed_calls
    end
  end

  describe '#get' do
    it 'sends no body and signs an empty body' do
      stubs.get('https://eu.api.ovh.com/1.0/sms/sms-aa12345-1') do |env|
        expect(env.body.to_s).to be_empty
        expect(env.request_headers['X-Ovh-Signature'])
          .to eq signature_for(method: 'GET', url: 'https://eu.api.ovh.com/1.0/sms/sms-aa12345-1', body: '')
        [200, { 'Content-Type': 'application/json' }, '{"foo":"bar"}']
      end

      client.get('/sms/sms-aa12345-1')
      stubs.verify_stubbed_calls
    end

    it 'serializes params into the query string' do
      stubs.get('https://eu.api.ovh.com/1.0/me/bill?date=2024&foo=bar') do
        [200, { 'Content-Type': 'application/json' }, '[]']
      end

      expect(client.get('/me/bill', { 'date' => '2024', 'foo' => 'bar' })).to eq([])
      stubs.verify_stubbed_calls
    end
  end

  describe 'log redaction' do
    it 'redacts OVH credential headers but keeps the non-secret timestamp' do
      line = [
        'X-Ovh-Application: app-key',
        'X-Ovh-Consumer: secret-ck',
        'X-Ovh-Signature: $1$deadbeef',
        'X-Ovh-Timestamp: 1700000000',
      ].join("\n")
      redacted = client.send(:log_filters).reduce(line) { |acc, (regex, repl)| acc.gsub(regex, repl) }

      expect(redacted).not_to include('app-key')
      expect(redacted).not_to include('secret-ck')
      expect(redacted).not_to include('deadbeef')
      expect(redacted).to include('1700000000')
    end

    it 'builds a client with a logger without error' do
      logger = Logger.new(StringIO.new)
      expect do
        described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz', logger: logger)
      end.not_to raise_error
    end

    it 'scrubs credential headers from real logged output' do
      io     = StringIO.new
      logged = Faraday.new(url: OvhRest::Client::OVH_API) do |b|
        client.send(:attach_logger, b, Logger.new(io))
        b.request :json
        b.adapter :test, stubs
      end
      logged_client = described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz',
                                          client: logged)
      stubs.get('https://eu.api.ovh.com/1.0/me') { [200, { 'Content-Type': 'application/json' }, '{}'] }

      logged_client.get('/me')

      expect(io.string).to include("X-Ovh-Consumer: #{OvhRest::Client::REDACTED}")
      expect(io.string).not_to include('X-Ovh-Signature: $1$')
    end
  end

  describe '#request_consumer_key' do
    let(:access_rules) { [{ 'method' => 'GET', 'path' => '/*' }] }

    it 'POSTs an unsigned credential request carrying only the application key' do
      stubs.post('https://eu.api.ovh.com/1.0/auth/credential') do |env|
        expect(env.body).to eq({ 'accessRules' => access_rules, 'redirection' => 'https://example.com' }.to_json)
        expect(env.request_headers['X-Ovh-Application']).to eq 'foo'
        expect(env.request_headers).not_to have_key('X-Ovh-Signature')
        [200, { 'Content-Type': 'application/json' }, '{"consumerKey":"ck","validationUrl":"https://val","state":"pendingValidation"}']
      end

      result = client.request_consumer_key(access_rules, redirection: 'https://example.com')

      expect(result).to eq({ 'consumerKey' => 'ck', 'validationUrl' => 'https://val', 'state' => 'pendingValidation' })
      stubs.verify_stubbed_calls
    end

    it 'omits redirection when not provided' do
      stubs.post('https://eu.api.ovh.com/1.0/auth/credential') do |env|
        expect(env.body).to eq({ 'accessRules' => access_rules }.to_json)
        [200, { 'Content-Type': 'application/json' }, '{"consumerKey":"ck"}']
      end

      client.request_consumer_key(access_rules)
      stubs.verify_stubbed_calls
    end

    it 'wraps an API failure in OvhRest::ApiError' do
      stubs.post('https://eu.api.ovh.com/1.0/auth/credential') do
        [400, { 'Content-Type': 'application/json' },
         '{"message":"Invalid access rules","errorCode":"INVALID_ARGUMENT"}',]
      end

      expect { client.request_consumer_key(access_rules) }.to raise_error(OvhRest::ClientError, 'Invalid access rules')
    end

    it 'wraps a transport failure in OvhRest::Error' do
      stubs.post('https://eu.api.ovh.com/1.0/auth/credential') { raise Faraday::ConnectionFailed, 'boom' }

      expect { client.request_consumer_key(access_rules) }.to raise_error(OvhRest::Error)
    end

    it 'rejects access_rules that are not a non-empty array of rule hashes' do
      expect { client.request_consumer_key({ 'method' => 'GET', 'path' => '/*' }) }.to raise_error(ArgumentError)
      expect { client.request_consumer_key([]) }.to raise_error(ArgumentError)
      expect { client.request_consumer_key(['GET /*']) }.to raise_error(ArgumentError)
    end
  end

  describe '#current_credential' do
    it 'GETs the signed /auth/currentCredential endpoint' do
      stubs.get('https://eu.api.ovh.com/1.0/auth/currentCredential') do |env|
        expect(env.request_headers).to have_key('X-Ovh-Signature')
        [200, { 'Content-Type': 'application/json' }, '{"credentialId":42,"status":"validated"}']
      end

      expect(client.current_credential).to eq({ 'credentialId' => 42, 'status' => 'validated' })
      stubs.verify_stubbed_calls
    end
  end

  describe 'clock skew' do
    it 'offsets the signed timestamp by the configured time_delta' do
      skewed  = described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz',
                                    time_delta: 120, client: conn)
      headers = skewed.build_headers(method: 'GET', path: '/me')

      expect(headers['X-Ovh-Timestamp']).to eq((frozen_time + 120).to_s)
    end

    it 'derives the time_delta from the OVH /auth/time endpoint' do
      stubs.get('https://eu.api.ovh.com/1.0/auth/time') do
        [200, { 'Content-Type': 'application/json' }, (frozen_time + 50).to_s]
      end

      expect(client.synchronize_time!).to eq 50
      expect(client.build_headers(method: 'GET', path: '/me')['X-Ovh-Timestamp']).to eq((frozen_time + 50).to_s)
      stubs.verify_stubbed_calls
    end

    it 'wraps a failure while synchronizing in OvhRest::Error' do
      stubs.get('https://eu.api.ovh.com/1.0/auth/time') { raise Faraday::ConnectionFailed, 'boom' }

      expect { client.synchronize_time! }.to raise_error(OvhRest::Error)
    end

    context 'with auto_sync_time enabled' do
      let(:auto_client) do
        described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz',
                            auto_sync_time: true, client: conn)
      end

      it 'synchronizes the clock exactly once, before the first signed request' do
        time_calls = 0
        stubs.get('https://eu.api.ovh.com/1.0/auth/time') do
          time_calls += 1
          [200, { 'Content-Type': 'application/json' }, (frozen_time + 30).to_s]
        end
        stubs.get('https://eu.api.ovh.com/1.0/me') do |env|
          expect(env.request_headers['X-Ovh-Timestamp']).to eq((frozen_time + 30).to_s)
          [200, { 'Content-Type': 'application/json' }, '{}']
        end

        auto_client.get('/me')
        auto_client.get('/me')

        expect(time_calls).to eq 1
      end

      it 'propagates a synchronization failure from the first request' do
        stubs.get('https://eu.api.ovh.com/1.0/auth/time') { raise Faraday::ConnectionFailed, 'boom' }

        expect { auto_client.get('/me') }.to raise_error(OvhRest::Error)
      end
    end
  end

  describe 'retries' do
    let(:retrying_client) do
      described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz', retries: 2,
                          client: retry_conn)
    end

    # A connection whose stack mirrors production: raise_error outside retry.
    let(:retry_conn) do
      Faraday.new(url: OvhRest::Client::OVH_API) do |b|
        b.response :raise_error
        b.request :retry, max: 2, interval: 0, retry_statuses: [503]
        b.request :json
        b.response :json
        b.adapter :test, stubs
      end
    end

    it 'retries a 503 and succeeds on the next attempt' do
      calls = 0
      stubs.get('https://eu.api.ovh.com/1.0/me') do
        calls += 1
        calls < 2 ? [503, {}, ''] : [200, { 'Content-Type': 'application/json' }, '{"ok":true}']
      end

      expect(retrying_client.get('/me')).to eq({ 'ok' => true })
      expect(calls).to eq 2
    end

    it 'wires retry inside raise_error so retriable statuses are seen before they raise' do
      handlers = described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz', retries: 3)
                                .instance_variable_get(:@client).builder.handlers
      expect(handlers).to include(Faraday::Retry::Middleware)
      expect(handlers.index(Faraday::Retry::Middleware)).to be > handlers.index(Faraday::Response::RaiseError)
    end

    it 'omits the retry middleware by default' do
      built = described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz')
                             .instance_variable_get(:@client)
      expect(built.builder.handlers).not_to include(Faraday::Retry::Middleware)
    end
  end

  describe 'error handling' do
    it 'wraps an OVH API error response in OvhRest::ApiError' do
      body = '{"message":"This call has not been granted","httpCode":"403 Forbidden","errorCode":"INVALID_CREDENTIAL"}'
      stubs.get('https://eu.api.ovh.com/1.0/me') do
        [403, { 'Content-Type': 'application/json' }, body]
      end

      expect { client.get('/me') }.to raise_error(OvhRest::ClientError) do |error|
        expect(error).to be_a(OvhRest::ApiError)
        expect(error.message).to eq 'This call has not been granted'
        expect(error.error_code).to eq 'INVALID_CREDENTIAL'
        expect(error.http_code).to eq '403 Forbidden'
        expect(error.status).to eq 403
      end
    end

    it 'raises OvhRest::ServerError with no envelope for a non-JSON 5xx body' do
      stubs.get('https://eu.api.ovh.com/1.0/me') do
        [502, { 'Content-Type': 'text/html' }, '<html>Bad Gateway</html>']
      end

      expect { client.get('/me') }.to raise_error(OvhRest::ServerError) do |error|
        expect(error).to be_a(OvhRest::ApiError)
        expect(error.status).to eq 502
        expect(error.error_code).to be_nil
      end
    end

    it 'maps statuses to error classes, falling back to ApiError' do
      expect(client.send(:error_class_for, 404)).to eq OvhRest::ClientError
      expect(client.send(:error_class_for, 503)).to eq OvhRest::ServerError
      expect(client.send(:error_class_for, 302)).to eq OvhRest::ApiError
    end

    it 'wraps errors raised by write verbs too' do
      stubs.put('https://eu.api.ovh.com/1.0/me') do
        [409, { 'Content-Type': 'application/json' }, '{"message":"Conflict","errorCode":"CONFLICT"}']
      end

      expect { client.put('/me', { 'a' => 1 }) }.to raise_error(OvhRest::ClientError, 'Conflict')
    end

    it 'wraps a transport failure in OvhRest::Error' do
      stubs.get('https://eu.api.ovh.com/1.0/me') { raise Faraday::TimeoutError }

      expect { client.get('/me') }.to raise_error(OvhRest::Error)
    end
  end

  describe '#post' do
    it 'sends the JSON body and signs it' do
      stubs.post('https://eu.api.ovh.com/1.0/sms/jobs') do |env|
        expect(env.body).to eq '{"message":"hi"}'
        expect(env.request_headers['X-Ovh-Signature'])
          .to eq signature_for(method: 'POST', url: 'https://eu.api.ovh.com/1.0/sms/jobs', body: '{"message":"hi"}')
        [200, { 'Content-Type': 'application/json' }, '{"ok":true}']
      end

      expect(client.post('/sms/jobs', { 'message' => 'hi' })).to eq({ 'ok' => true })
      stubs.verify_stubbed_calls
    end

    it 'signs and sends a non-ASCII body byte-for-byte identically' do
      body = { 'message' => 'héllo 🎉' }.to_json

      stubs.post('https://eu.api.ovh.com/1.0/sms/jobs') do |env|
        expect(env.body).to eq body
        expect(env.request_headers['X-Ovh-Signature'])
          .to eq signature_for(method: 'POST', url: 'https://eu.api.ovh.com/1.0/sms/jobs', body: body)
        [200, { 'Content-Type': 'application/json' }, '{"ok":true}']
      end

      client.post('/sms/jobs', { 'message' => 'héllo 🎉' })
      stubs.verify_stubbed_calls
    end
  end

  describe '#put' do
    it 'sends the JSON body, signs it and returns the parsed response' do
      stubs.put('https://eu.api.ovh.com/1.0/me') do |env|
        expect(env.body).to eq '{"name":"new"}'
        expect(env.request_headers['X-Ovh-Signature'])
          .to eq signature_for(method: 'PUT', url: 'https://eu.api.ovh.com/1.0/me', body: '{"name":"new"}')
        [200, { 'Content-Type': 'application/json' }, '{"ok":true}']
      end

      expect(client.put('/me', { 'name' => 'new' })).to eq({ 'ok' => true })
      stubs.verify_stubbed_calls
    end
  end

  describe 'bodyless edge cases' do
    it 'sends an empty body for a POST with no params' do
      url = 'https://eu.api.ovh.com/1.0/sms/jobs'
      stubs.post(url) do |env|
        expect(env.body.to_s).to be_empty
        expect(env.request_headers['X-Ovh-Signature']).to eq signature_for(method: 'POST', url: url, body: '')
        [200, { 'Content-Type': 'application/json' }, '{}']
      end

      client.post('/sms/jobs')
      stubs.verify_stubbed_calls
    end

    it 'sends a bodyless request to the bare path for a DELETE with no params' do
      url = 'https://eu.api.ovh.com/1.0/me/api/credential/42'
      stubs.delete(url) do |env|
        expect(env.body.to_s).to be_empty
        [200, { 'Content-Type': 'application/json' }, 'null']
      end

      expect(client.delete('/me/api/credential/42')).to be_nil
      stubs.verify_stubbed_calls
    end
  end

  describe 'custom request headers' do
    it 'merges caller-supplied headers (e.g. OVH batch) without affecting the signature' do
      url = 'https://eu.api.ovh.com/1.0/dedicated/server'
      stubs.get(url) do |env|
        expect(env.request_headers['X-Ovh-Batch']).to eq ','
        expect(env.request_headers['X-Ovh-Signature']).to eq signature_for(method: 'GET', url: url, body: '')
        [200, { 'Content-Type': 'application/json' }, '[]']
      end

      client.get('/dedicated/server', {}, headers: { 'X-Ovh-Batch' => ',' })
      stubs.verify_stubbed_calls
    end

    it 'never lets custom headers override the OVH auth headers' do
      stubs.get('https://eu.api.ovh.com/1.0/me') do |env|
        expect(env.request_headers['X-Ovh-Application']).to eq 'foo'
        [200, { 'Content-Type': 'application/json' }, '{}']
      end

      client.get('/me', {}, headers: { 'X-Ovh-Application' => 'evil' })
      stubs.verify_stubbed_calls
    end
  end

  describe '#head' do
    it 'sends a bodyless signed request' do
      url = 'https://eu.api.ovh.com/1.0/me'
      stubs.head(url) do |env|
        expect(env.body.to_s).to be_empty
        expect(env.request_headers['X-Ovh-Signature']).to eq signature_for(method: 'HEAD', url: url, body: '')
        [200, { 'Content-Type': 'application/json' }, '']
      end

      client.head('/me')
      stubs.verify_stubbed_calls
    end
  end

  describe '#patch' do
    it 'sends the JSON body and signs it' do
      stubs.patch('https://eu.api.ovh.com/1.0/me') do |env|
        expect(env.body).to eq '{"name":"new"}'
        expect(env.request_headers['X-Ovh-Signature'])
          .to eq signature_for(method: 'PATCH', url: 'https://eu.api.ovh.com/1.0/me', body: '{"name":"new"}')
        [200, { 'Content-Type': 'application/json' }, '{"ok":true}']
      end

      client.patch('/me', { 'name' => 'new' })
      stubs.verify_stubbed_calls
    end
  end

  describe '#delete' do
    it 'sends no body and serializes params into the query string' do
      stubs.delete('https://eu.api.ovh.com/1.0/me/api/credential?status=expired') do |env|
        expect(env.body.to_s).to be_empty
        expect(env.request_headers['X-Ovh-Signature'])
          .to eq signature_for(method: 'DELETE', url: 'https://eu.api.ovh.com/1.0/me/api/credential?status=expired',
                               body: '')
        [200, { 'Content-Type': 'application/json' }, 'null']
      end

      client.delete('/me/api/credential', { 'status' => 'expired' })
      stubs.verify_stubbed_calls
    end
  end
end
