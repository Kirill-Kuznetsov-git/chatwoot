require 'rails_helper'

describe Care::Sla::TickJob do
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }
  let(:account) { create(:account) }
  let(:config) { Care::Queue::Config.new(Care::Queue::Defaults::SETTINGS, version: 1, source: 'test') }
  let(:whale) { create(:contact, account: account, identifier: 'a1' * 12, custom_attributes: { 'segment_weight' => 'Whale' }) }
  let(:minnow) { create(:contact, account: account, identifier: 'b2' * 12, custom_attributes: { 'segment_weight' => 'Small Fish' }) }

  around { |example| with_modified_env(env) { example.run } }

  before do
    allow(Care::Queue::Config).to receive(:current).and_return(config)
    Redis::Alfred.delete(described_class::LOCK_KEY)
  end

  it 'reconciles active trackers and sweeps open queue conversations that have none' do
    tracked = create(:conversation, account: account, contact: whale, status: :open)
    Care::SlaTracker.create!(account: account, conversation: tracked, contact: whale, class_key: 'vip', class_name: 'VIP',
                             started_at: 5.minutes.ago)
    missed = create(:conversation, account: account, contact: whale, status: :open)
    handoff = 40.minutes.ago.change(usec: 0)
    ReportingEvent.create!(name: 'conversation_bot_handoff', account_id: account.id, inbox_id: missed.inbox_id, conversation_id: missed.id,
                           value: 1, created_at: handoff)
    create(:conversation, account: account, contact: minnow, status: :open)
    create(:conversation, account: account, contact: whale, status: :resolved)

    stats = described_class.perform_now

    expect(stats).to eq(reconciled: 1, errors: 0, swept: 1)
    expect(tracked.reload.priority).to eq('urgent')
    swept = Care::SlaTracker.find_by(conversation_id: missed.id)
    expect(swept).to have_attributes(class_key: 'vip', fr_state: 'breached')
    expect(swept.started_at).to be_within(1.second).of(handoff)
    expect(Care::SlaTracker.count).to eq(2)
    expect(Redis::Alfred.get(described_class::LOCK_KEY)).to be_nil
  end

  it 'skips the tick while another one holds the lock' do
    Redis::Alfred.set(described_class::LOCK_KEY, '1', ex: 30)
    create(:conversation, account: account, contact: whale, status: :open)

    expect(described_class.perform_now).to be_nil
    expect(Care::SlaTracker.count).to eq(0)
    Redis::Alfred.delete(described_class::LOCK_KEY)
  end

  it 'isolates a failing tracker and keeps going' do
    broken = create(:conversation, account: account, contact: whale, status: :open)
    tracker = Care::SlaTracker.create!(account: account, conversation: broken, contact: whale, class_key: 'vip', class_name: 'VIP',
                                       started_at: 1.minute.ago)
    allow(Care::Sla::Reconciler).to receive(:new).and_call_original
    allow(Care::Sla::Reconciler).to receive(:new).with(tracker, anything).and_raise(StandardError, 'boom')
    fine = create(:conversation, account: account, contact: whale, status: :open)

    stats = described_class.perform_now
    expect(stats).to include(errors: 1, swept: 1)
    expect(Care::SlaTracker.find_by(conversation_id: fine.id)).to be_present
  end
end
