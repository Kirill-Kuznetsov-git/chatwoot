require 'rails_helper'

RSpec.describe Care::SegmentSyncJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, identifier: 'c3' * 12) }
  let(:url) { "https://care.test/api/users/#{contact.identifier}/segment" }
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }
  let(:segment) do
    { role: 'Trader', weight: 'Mega Whale', tier_90d: 'Big', label: '🐳 Mega Whale Trader', priority_rank: 0, source: 'metabase' }
  end

  def stub_care(status: 200, body: segment)
    stub_request(:get, url).to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'is enqueued on the low queue' do
    expect(described_class.new.queue_name).to eq('low')
  end

  it 'writes the segment into the contact attributes' do
    stub = stub_care
    with_modified_env(env) { described_class.perform_now(contact.id) }

    expect(stub).to have_been_requested.once
    expect(contact.reload.custom_attributes).to include(
      'segment_role' => 'Trader', 'segment_weight' => 'Mega Whale', 'segment_tier_90d' => 'Big',
      'segment_label' => '🐳 Mega Whale Trader', 'segment_priority' => 0
    )
    expect(contact.custom_attributes['segment_synced_at']).to be_present
  end

  it 'writes the default segment for users without deals too' do
    stub_care(body: { role: 'Newcomer', weight: 'No Purchases', tier_90d: nil, label: '🌊 No Purchases Newcomer',
                      priority_rank: 63, source: 'default' })
    with_modified_env(env) { described_class.perform_now(contact.id) }

    expect(contact.reload.custom_attributes).to include('segment_role' => 'Newcomer', 'segment_priority' => 63)
    expect(contact.custom_attributes).not_to have_key('segment_tier_90d')
  end

  it 'does nothing when the integration is disabled' do
    stub = stub_care
    with_modified_env(env.merge(CARE_SEGMENT_SYNC_ENABLED: 'false')) { described_class.perform_now(contact.id) }
    expect(stub).not_to have_been_requested
  end

  it 'skips contacts without a valid StarPets identifier, other accounts and missing contacts' do
    stub = stub_request(:get, %r{care\.test/api/users/}).to_return(status: 200, body: segment.to_json)
    email_only = create(:contact, :with_email, account: account)
    with_modified_env(env) do
      described_class.perform_now(email_only.id)
      described_class.perform_now(contact.id + 100_000)
    end
    with_modified_env(env.merge(CARE_SEGMENT_SYNC_ACCOUNT_ID: (account.id + 1).to_s)) { described_class.perform_now(contact.id) }
    expect(stub).not_to have_been_requested
  end

  it 'skips a fresh contact unless forced' do
    contact.update!(custom_attributes: { 'segment_synced_at' => 10.minutes.ago.utc.iso8601, 'segment_label' => 'old' })
    stub = stub_care
    with_modified_env(env) do
      described_class.perform_now(contact.id)
      expect(stub).not_to have_been_requested
      described_class.perform_now(contact.id, force: true)
    end
    expect(stub).to have_been_requested.once
    expect(contact.reload.custom_attributes['segment_label']).to eq('🐳 Mega Whale Trader')
  end

  it 'discards the job on 403 and logs instead of retrying' do
    stub_care(status: 403, body: { detail: { code: 'FORBIDDEN' } })
    allow(Rails.logger).to receive(:error)
    with_modified_env(env) do
      expect { described_class.perform_now(contact.id) }.not_to raise_error
      expect(described_class).not_to have_been_enqueued
    end
    expect(Rails.logger).to have_received(:error).with(/discarded.*Unauthorized/)
    expect(contact.reload.custom_attributes).to eq({})
  end

  it 'retries when Care is unavailable' do
    stub_care(status: 503, body: {})
    with_modified_env(env) do
      expect { described_class.perform_now(contact.id) }.to have_enqueued_job(described_class).with(contact.id)
    end
    expect(contact.reload.custom_attributes).to eq({})
  end
end
