require 'rails_helper'

describe Care::Sla::DigestJob do
  let(:env) { { CARE_SEGMENT_SYNC_ENABLED: 'true', CARE_API_URL: 'https://care.test', CARE_SERVICE_KEY: 'k' } }
  let(:account) { create(:account) }
  let(:config) { Care::Queue::Config.new(Care::Queue::Defaults::SETTINGS.merge('digest_hour_utc' => 6), version: 2, source: 'test') }
  let(:contact) { create(:contact, account: account, identifier: 'a1' * 12, custom_attributes: { 'segment_weight' => 'Whale' }) }
  let(:yesterday) { Time.utc(2026, 9, 8, 12, 0) }

  around { |example| with_modified_env(env) { example.run } }

  before do
    allow(Care::Queue::Config).to receive(:current).and_return(config)
    Redis::Alfred.delete('care:sla:digest:2026-09-08')
    [[yesterday, yesterday + 20.minutes, nil], [yesterday + 1.hour, yesterday + 3.hours, yesterday + 1.hour + 30.minutes],
     [yesterday + 2.hours, nil, nil]].each do |started, replied, breached|
      conversation = create(:conversation, account: account, contact: contact, status: :open)
      Care::SlaTracker.create!(account: account, conversation: conversation, contact: contact, class_key: 'vip', class_name: 'VIP',
                               started_at: started, first_response_at: replied, fr_breached_at: breached, fr_state: replied ? 'met' : 'ok')
    end
  end

  it 'posts one digest per day at the configured hour' do
    travel_to Time.utc(2026, 9, 9, 6, 5) do
      expect(Care::Sla::Notifier).to receive(:digest).once do |text|
        expect(text).to include('SLA-дайджест за 08.09.2026', 'конфиг v2', 'VIP: передач людям 3, ответил человек 2',
                                'p50 20 мин, p90 120 мин', 'в KPI 360 мин — 100 %', 'нарушений: первый ответ 1', 'Big: передач людям 0',
                                'Сейчас в очереди людей: 3 диалогов')
      end
      described_class.perform_now
      described_class.perform_now
    end
  end

  it 'stays quiet outside the hour or when disabled, unless forced' do
    expect(Care::Sla::Notifier).not_to receive(:digest)
    travel_to(Time.utc(2026, 9, 9, 7, 5)) { described_class.perform_now }

    allow(Care::Queue::Config).to receive(:current).and_return(
      Care::Queue::Config.new(Care::Queue::Defaults::SETTINGS.merge('digest_enabled' => false), version: 3, source: 'test')
    )
    travel_to(Time.utc(2026, 9, 9, 6, 5)) { described_class.perform_now }
  end

  it 'force sends for a given date regardless of hour and dedupe' do
    expect(Care::Sla::Notifier).to receive(:digest).twice
    travel_to Time.utc(2026, 9, 9, 15, 0) do
      described_class.perform_now('2026-09-08', force: true)
      described_class.perform_now('2026-09-08', force: true)
    end
  end
end
