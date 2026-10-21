require 'rails_helper'

RSpec.describe ManualEscalations::WebhookJob do
  let(:account) { create(:account) }
  let(:url) { 'https://example.com/manual-escalation' }
  let(:webhook) { create(:webhook, account: account, inbox_id: nil, name: 'manual_escalation', url: url, subscriptions: ['conversation_updated']) }
  let(:payload) { { event: 'conversation_updated', id: 1, account: { id: account.id }, inbox_id: 1, labels: ['escalated'], status: 'open' } }

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s, MANUAL_ESCALATION_WEBHOOK_URLS: url) { example.run }
  end

  it 'signs the exact minimal body and keeps the delivery identifier' do
    expect(SafeFetch).to receive(:fetch) do |request_url, **options|
      expect(request_url).to eq(url)
      expect(options[:body]).to eq(payload.to_json)
      headers = options[:headers]
      expect(headers['X-Chatwoot-Delivery']).to eq('delivery-1')
      signature = OpenSSL::HMAC.hexdigest('SHA256', webhook.secret, "#{headers['X-Chatwoot-Timestamp']}.#{options[:body]}")
      expect(headers['X-Chatwoot-Signature']).to eq("sha256=#{signature}")
    end
    described_class.perform_now(webhook.id, payload, delivery_id: 'delivery-1')
  end

  it 'retries a transient failure with exactly the same payload and delivery identifier' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('timeout'))
    clear_enqueued_jobs
    described_class.perform_now(webhook.id, payload, delivery_id: 'delivery-1')
    expect(described_class).to have_been_enqueued.with(webhook.id, payload, delivery_id: 'delivery-1')
    expect(enqueued_jobs.to_json).not_to include(webhook.secret, url)
  end

  it 'raises after ten failed attempts so Sidekiq can retain retry and dead-job visibility' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Unavailable'))
    clear_enqueued_jobs
    expect do
      perform_enqueued_jobs do
        described_class.perform_later(webhook.id, payload, delivery_id: 'delivery-1')
      end
    end.to raise_error(Minitest::UnexpectedError) { |error| expect(error.error.class.name).to eq('Webhooks::Trigger::RetryableError') }
    expect(SafeFetch).to have_received(:fetch).exactly(10).times
  end

  it 'delivers successfully on the second attempt after a timeout' do
    attempts = 0
    allow(SafeFetch).to receive(:fetch) do
      attempts += 1
      raise SafeFetch::FetchError, 'timeout' if attempts == 1
    end
    perform_enqueued_jobs do
      described_class.perform_later(webhook.id, payload, delivery_id: 'delivery-1')
    end
    expect(attempts).to eq(2)
  end

  it 'skips queued delivery when the feature is disabled' do
    expect(SafeFetch).not_to receive(:fetch)
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: '') do
      described_class.perform_now(webhook.id, payload, delivery_id: 'delivery-1')
    end
  end

  it 'does not deliver an event from another inbox to a bound hook' do
    webhook.update!(inbox_id: 2)
    expect(SafeFetch).not_to receive(:fetch)
    described_class.perform_now(webhook.id, payload, delivery_id: 'delivery-1')
  end

  it 'refuses unsigned delivery' do
    expect(SafeFetch).not_to receive(:fetch)
    expect { described_class.perform_now(webhook.id, payload) }.to raise_error(ArgumentError)
  end
end
