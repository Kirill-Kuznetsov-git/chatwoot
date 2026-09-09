require 'rails_helper'

describe Care::Sla::ConversationPresenter do
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, identifier: 'a1' * 12, custom_attributes: { 'segment_weight' => 'Whale' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact, status: :open) }
  let(:started_at) { Time.zone.parse('2026-09-09 10:00:00 UTC') }
  let!(:tracker) do
    Care::SlaTracker.create!(account: account, conversation: conversation, contact: contact, class_key: 'vip', class_name: 'VIP',
                             started_at: started_at, fr_due_at: started_at + 30.minutes, nr_due_at: started_at + 60.minutes,
                             res_due_at: started_at + 12.hours)
  end

  def with_timer(enabled, &)
    settings = Care::Queue::Defaults::SETTINGS.merge('sla_timer_enabled' => enabled)
    allow(Care::Queue::Config).to receive(:current).and_return(Care::Queue::Config.new(settings, version: 3, source: 'test'))
    with_modified_env(env, &)
  end

  it 'returns due times in the shape the built-in SLA timer expects' do
    result = with_timer(true) { described_class.for(conversation) }

    expect(result).to eq(id: tracker.id, sla_name: 'VIP', sla_frt_due_at: (started_at + 30.minutes).to_i,
                         sla_nrt_due_at: (started_at + 60.minutes).to_i, sla_rt_due_at: (started_at + 12.hours).to_i)
  end

  it 'omits clocks that are not running' do
    tracker.update!(nr_due_at: nil)
    result = with_timer(true) { described_class.for(conversation) }

    expect(result[:sla_nrt_due_at]).to be_nil
    expect(result[:sla_frt_due_at]).to be_present
  end

  it 'stays silent while the timer is switched off in the Care config' do
    expect(with_timer(false) { described_class.for(conversation) }).to be_nil
  end

  it 'stays silent for conversations outside the queue and for closed trackers' do
    plain = create(:conversation, account: account, status: :open)
    expect(with_timer(true) { described_class.for(plain) }).to be_nil

    tracker.update!(active: false, closed_reason: 'resolved')
    expect(with_timer(true) { described_class.for(conversation) }).to be_nil
  end

  it 'stays silent when the whole Care integration is disabled' do
    allow(Care::Queue::Config).to receive(:current).and_return(
      Care::Queue::Config.new(Care::Queue::Defaults::SETTINGS.merge('sla_timer_enabled' => true), version: 3, source: 'test')
    )
    expect(described_class.for(conversation)).to be_nil
  end
end
