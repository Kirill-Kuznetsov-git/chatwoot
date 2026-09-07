require 'rails_helper'

describe Care::Queue::Applier do
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, identifier: 'a1' * 12, custom_attributes: { 'segment_weight' => 'Whale' }) }
  let(:config) { Care::Queue::Config.new(Care::Queue::Defaults::SETTINGS, version: 1, source: 'test') }
  let(:now) { Time.zone.parse('2026-09-08 10:00:00 UTC') }

  around { |example| with_modified_env(env) { example.run } }

  it 'pending (still with the bot): class priority and label right away, no tracker yet' do
    conversation = create(:conversation, account: account, contact: contact, status: :pending)

    expect(described_class.apply!(conversation, config: config, now: now)).to be_nil
    expect(conversation.reload.priority).to eq('urgent')
    expect(conversation.label_list).to contain_exactly('vip')
    expect(Care::SlaTracker.where(conversation: conversation)).to be_empty
  end

  it 'open: creates the tracker anchored at started_at and reconciles immediately' do
    conversation = create(:conversation, account: account, contact: contact, status: :open, priority: :urgent, waiting_since: nil)
    handoff = now - 40.minutes

    tracker = described_class.apply!(conversation, config: config, now: now, started_at: handoff)

    expect(tracker).to have_attributes(class_key: 'vip', started_at: handoff, active: true, fr_state: 'breached', priority_applied: 'urgent')
    expect(tracker.fr_breached_at).to eq(handoff + 30.minutes)
    expect(conversation.reload.label_list).to contain_exactly('vip')
    expect(described_class.apply!(conversation, config: config, now: now + 1.minute).id).to eq(tracker.id)
  end

  it 'resolved conversation without a tracker is left alone' do
    conversation = create(:conversation, account: account, contact: contact, status: :resolved)
    expect(described_class.apply!(conversation, config: config, now: now)).to be_nil
    expect(Care::SlaTracker.count).to eq(0)
  end

  it 'reopening a resolved tracker restarts the resolution clock from the reopen' do
    conversation = create(:conversation, account: account, contact: contact, status: :open, waiting_since: nil)
    tracker = described_class.apply!(conversation, config: config, now: now)
    conversation.resolved!
    described_class.apply!(conversation, config: config, now: now + 10.minutes)
    expect(tracker.reload).to have_attributes(active: false, closed_reason: 'resolved')

    conversation.open!
    described_class.apply!(conversation, config: config, now: now + 1.day)
    expect(tracker.reload).to have_attributes(active: true, closed_reason: nil, resolved_at: nil, reopened_at: now + 1.day,
                                              res_due_at: now + 1.day + 12.hours, started_at: now)
  end

  it 'a contact outside the queue untracks an active tracker and does nothing otherwise' do
    conversation = create(:conversation, account: account, contact: contact, status: :open)
    tracker = described_class.apply!(conversation, config: config, now: now)
    contact.update!(custom_attributes: { 'segment_weight' => 'Small Fish' })

    expect(described_class.apply!(conversation, config: config, now: now + 1.minute)).to be_nil
    expect(tracker.reload.closed_reason).to eq('untracked')
    expect(conversation.reload.priority).to be_nil

    plain = create(:conversation, account: account, status: :open)
    expect(described_class.apply!(plain, config: config, now: now)).to be_nil
    expect(Care::SlaTracker.count).to eq(1)
  end

  it 'does nothing when the integration is off or for another account' do
    conversation = create(:conversation, account: account, contact: contact, status: :open)
    with_modified_env(CARE_SEGMENT_SYNC_ENABLED: 'false') do
      expect(described_class.apply!(conversation, config: config, now: now)).to be_nil
    end
    with_modified_env(CARE_SEGMENT_SYNC_ACCOUNT_ID: (account.id + 1).to_s) do
      expect(described_class.apply!(conversation, config: config, now: now)).to be_nil
    end
    expect(Care::SlaTracker.count).to eq(0)
    expect(conversation.reload.priority).to be_nil
  end
end
