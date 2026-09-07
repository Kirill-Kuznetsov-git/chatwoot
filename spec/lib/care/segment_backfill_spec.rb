require 'rails_helper'

describe Care::SegmentBackfill do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:ids) { (1..5).map { |i| i.to_s.rjust(24, '0') } }
  let(:client) { instance_double(Care::Client) }
  let(:sleeps) { [] }
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, warn: nil) }
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }

  def backfill(**)
    described_class.new(account: account, client: client, rate_per_minute: 600, page_size: 3, logger: logger,
                        sleeper: ->(s) { sleeps << s }, **)
  end

  def segment_for(id)
    { 'role' => 'Seller', 'weight' => 'Big Whale', 'tier_90d' => 'Big', 'label' => '🐋 Big Whale Seller', 'priority_rank' => 10,
      'user_id' => id }
  end

  before do
    # 5 ценных id в Care; в Chatwoot есть контакты для 1, 2 (свежий), 4 и для 3 — но в другом аккаунте
    create(:contact, account: account, identifier: ids[0])
    create(:contact, account: account, identifier: ids[1],
                     custom_attributes: { 'segment_synced_at' => 5.minutes.ago.utc.iso8601, 'segment_label' => 'fresh' })
    create(:contact, account: other_account, identifier: ids[2])
    create(:contact, account: account, identifier: ids[3])
    allow(client).to receive(:valuable_user_ids).with(after_id: nil, limit: 3)
                                                .and_return({ 'user_ids' => ids[0, 3], 'next_after_id' => ids[2], 'total' => 5 })
    allow(client).to receive(:valuable_user_ids).with(after_id: ids[2], limit: 3)
                                                .and_return({ 'user_ids' => ids[3, 2], 'next_after_id' => nil, 'total' => 5 })
    allow(client).to receive(:segment) { |id| segment_for(id) }
  end

  it 'syncs only the matching, non-fresh contacts of the account and rate-limits' do
    result = with_modified_env(env) { backfill.run }

    expect(result.to_h).to include(pages: 2, ids_seen: 5, contacts_found: 3, synced: 2, changed: 2, skipped_fresh: 1, failed: 0,
                                   last_after_id: ids[4])
    expect(account.contacts.find_by(identifier: ids[0]).custom_attributes['segment_label']).to eq('🐋 Big Whale Seller')
    expect(account.contacts.find_by(identifier: ids[3]).custom_attributes['segment_label']).to eq('🐋 Big Whale Seller')
    expect(account.contacts.find_by(identifier: ids[1]).custom_attributes['segment_label']).to eq('fresh')
    expect(other_account.contacts.find_by(identifier: ids[2]).custom_attributes).to eq({})
    expect(sleeps).to eq([0.1, 0.1])
  end

  it 'counts and does not write in dry-run' do
    result = with_modified_env(env) { backfill(dry_run: true).run }

    expect(result.to_h).to include(contacts_found: 3, synced: 0, skipped_fresh: 1)
    expect(account.contacts.find_by(identifier: ids[0]).custom_attributes).to eq({})
    expect(client).not_to have_received(:segment)
  end

  it 'continues past a failing contact and backs off when Care is unavailable' do
    allow(client).to receive(:segment) do |id|
      raise Care::Client::Unavailable, 'care: HTTP 503' if id == ids[0]

      segment_for(id)
    end
    result = with_modified_env(env) { backfill.run }

    expect(result.to_h).to include(synced: 1, failed: 1, changed: 1)
    expect(logger).to have_received(:warn).with(/failed: Care::Client::Unavailable/)
    expect(sleeps).to eq([0.5, 0.1, 0.1]) # backoff после сбоя, затем обычный шаг после каждого контакта
  end

  it 'resumes from after_id' do
    result = with_modified_env(env) { backfill.run(after_id: ids[2]) }

    expect(client).not_to have_received(:valuable_user_ids).with(after_id: nil, limit: 3)
    expect(result.to_h).to include(pages: 1, ids_seen: 2, contacts_found: 1, synced: 1)
  end
end
