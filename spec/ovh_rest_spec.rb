# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OvhRest do
  describe '.new' do
    it 'builds a configured client' do
      client = described_class.new(application_key: 'foo', application_secret: 'bar', consumer_key: 'baz')

      expect(client).to be_a(OvhRest::Client)
      expect(client.api_uri).to eq 'https://eu.api.ovh.com/1.0'
    end
  end

  describe '.gem_version' do
    it 'returns the gem version' do
      expect(described_class.gem_version).to be_a(Gem::Version)
      expect(described_class.gem_version.to_s).to eq OvhRest::VERSION::STRING
    end
  end

  describe 'error hierarchy' do
    it 'nests API errors under OvhRest::Error' do
      expect(OvhRest::ApiError.ancestors).to include(OvhRest::Error)
      expect(OvhRest::ClientError.ancestors).to include(OvhRest::ApiError)
      expect(OvhRest::ServerError.ancestors).to include(OvhRest::ApiError)
    end
  end
end
