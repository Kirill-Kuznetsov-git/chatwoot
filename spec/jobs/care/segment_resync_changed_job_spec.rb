require 'rails_helper'

RSpec.describe Care::SegmentResyncChangedJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:ids) { (1..4).map { |i| i.to_s.rjust(24, '0') } }
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }
  let(:client) { instance_double(Care::Client) }

  before do
    allow(Care::Client).to receive(:new).and_return(client)
    create(:contact, account: account, identifier: ids[0])
    create(:contact, account: account, identifier: ids[2])
    create(:contact, account: other_account, identifier: ids[3])
  end

  it 'is scheduled daily on the low queue after the Care nightly run' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))['care_segment_resync_changed_job']
    expect(schedule).to include('class' => 'Care::SegmentResyncChangedJob', 'cron' => '30 3 * * *', 'queue' => 'low')
    expect(described_class.new.queue_name).to eq('low')
  end

  it 'enqueues a forced sync for every matching contact across pages' do
    allow(client).to receive(:changed_user_ids).with(since: kind_of(Time), after_id: nil, limit: 1000)
                                               .and_return({ 'user_ids' => ids[0, 2], 'next_after_id' => ids[1] })
    allow(client).to receive(:changed_user_ids).with(since: kind_of(Time), after_id: ids[1], limit: 1000)
                                               .and_return({ 'user_ids' => ids[2, 2], 'next_after_id' => nil })

    stats = with_modified_env(env) { described_class.perform_now }

    expect(stats).to eq(pages: 2, ids: 4, contacts: 3)
    expect(Care::SegmentSyncJob).to have_been_enqueued.exactly(3).times
    expect(Care::SegmentSyncJob).to have_been_enqueued.with(account.contacts.find_by(identifier: ids[0]).id, force: true)
    expect(Care::SegmentSyncJob).to have_been_enqueued.with(other_account.contacts.find_by(identifier: ids[3]).id, force: true)
  end

  it 'respects the account restriction and an explicit since' do
    allow(client).to receive(:changed_user_ids).with(since: Time.zone.parse('2026-09-07T00:00:00Z'), after_id: nil, limit: 1000)
                                               .and_return({ 'user_ids' => ids, 'next_after_id' => nil })

    stats = with_modified_env(env.merge(CARE_SEGMENT_SYNC_ACCOUNT_ID: account.id.to_s)) do
      described_class.perform_now('2026-09-07T00:00:00Z')
    end

    expect(stats).to eq(pages: 1, ids: 4, contacts: 2)
    expect(Care::SegmentSyncJob).to have_been_enqueued.exactly(2).times
  end

  it 'does nothing when disabled' do
    expect(client).not_to receive(:changed_user_ids)
    expect(described_class.perform_now).to be_nil
  end
end
