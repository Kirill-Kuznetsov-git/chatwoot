require 'rails_helper'

RSpec.describe Webhooks::Trigger do
  let(:url) { 'https://example.com/manual-escalation' }
  let(:payload) { { event: 'conversation_updated', id: 1 } }

  [SafeFetch::FetchError.new('timeout'), SafeFetch::HttpError.new('429 Too Many Requests'),
   SafeFetch::HttpError.new('503 Unavailable')].each do |error|
    it "retries a dedicated manual escalation webhook after #{error.message}" do
      allow(SafeFetch).to receive(:fetch).and_raise(error)
      expect do
        described_class.execute(url, payload, :manual_escalation_webhook, secret: 'test-secret', delivery_id: 'delivery-1')
      end.to raise_error(Webhooks::Trigger::RetryableError)
    end
  end

  it 'does not retry an ordinary account webhook or change its existing failure behavior' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Unavailable'))
    expect { described_class.execute(url, payload, :account_webhook) }.not_to raise_error
  end

  it 'does not retry a permanent bad request' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('400 Bad Request'))
    expect do
      described_class.execute(url, payload, :manual_escalation_webhook, secret: 'test-secret', delivery_id: 'delivery-1')
    end.not_to raise_error
  end
end
