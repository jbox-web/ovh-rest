# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OvhRest::Client do
  # Faraday test adapter
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  # Faraday::Connection object that uses the test adapter
  let(:conn) { Faraday.new(url: OvhRest::Client::OVH_API) { |b| b.adapter(:test, stubs) } }

  # WeatherClient with the stubbed connection object injected
  let(:client) { described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz').tap { |o| o.client = conn } } # rubocop:disable Layout/LineLength

  # Clear default connection to prevent it from being cached between different tests.
  # This allows for each test to have its own set of stubs
  after do
    Faraday.default_connection = nil
  end

  describe '#api_uri' do
    it 'returns ovh api url with version' do
      expect(client.api_uri).to eq 'https://eu.api.ovh.com/1.0'
    end
  end

  describe '#build_headers' do
    # rubocop:disable RSpec/ExampleLength, Layout/LineLength
    it 'calls ovh api' do
      headers = client.build_headers(method: 'GET', path: '/sms/sms-aa12345-1')

      application_secret = 'bar'
      consumer_key       = 'baz'
      method             = 'GET'
      url                = 'https://eu.api.ovh.com/1.0/sms/sms-aa12345-1'
      body               = {}.to_json
      timestamp          = Time.now.to_i.to_s
      signature          = "$1$#{Digest::SHA1.hexdigest("#{application_secret}+#{consumer_key}+#{method}+#{url}+#{body}+#{timestamp}")}"

      expect(headers).to eq({
        'X-Ovh-Application' => 'foo',
        'X-Ovh-Consumer'    => 'baz',
        'X-Ovh-Signature'   => signature,
        'X-Ovh-Timestamp'   => timestamp,
      })
    end
    # rubocop:enable RSpec/ExampleLength, Layout/LineLength
  end

  # rubocop:disable RSpec/NoExpectationExample
  describe '#query' do
    it 'calls ovh api' do
      stubs.get('https://eu.api.ovh.com/1.0/sms/sms-aa12345-1') do
        [200, { 'Content-Type': 'application/json' }, '{"foo":"bar"}']
      end
      client.query(method: 'GET', path: '/sms/sms-aa12345-1')
      stubs.verify_stubbed_calls
    end
  end

  describe '#get' do
    it 'calls ovh api' do
      stubs.get('https://eu.api.ovh.com/1.0/sms/sms-aa12345-1') do
        [200, { 'Content-Type': 'application/json' }, '{"foo":"bar"}']
      end

      client.get('/sms/sms-aa12345-1')
      stubs.verify_stubbed_calls
    end
  end
  # rubocop:enable RSpec/NoExpectationExample
end
