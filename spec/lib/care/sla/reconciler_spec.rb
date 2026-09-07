require 'rails_helper'

describe Care::Sla::Reconciler do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, identifier: 'a1' * 12,
                     custom_attributes: { 'segment_weight' => 'Whale', 'segment_tier_90d' => 'Small', 'segment_label' => '🦈 Whale Buyer' })
  end
  let(:started_at) { Time.zone.parse('2026-09-08 10:00:00 UTC') }
  # фабрика ставит waiting_since = сейчас (реальное время), а часы в примерах идут от фиксированного started_at — обнуляем
  let(:conversation) do
    create(:conversation, account: account, contact: contact, status: :open).tap { |c| c.update_columns(waiting_since: nil) } # rubocop:disable Rails/SkipsModelValidations
  end
  let(:tracker) do
    Care::SlaTracker.create!(account: account, conversation: conversation, contact: contact, class_key: 'vip', class_name: 'VIP',
                             started_at: started_at)
  end
  let(:overrides) { {} }
  let(:settings) { Care::Queue::Defaults::SETTINGS.merge(overrides) }
  let(:config) { Care::Queue::Config.new(settings, version: 7, source: 'test') }
  let(:notifier) { class_double(Care::Sla::Notifier, breach: true) }

  def reconcile(at:, with: config)
    described_class.new(tracker, config: with, now: at, notifier: notifier).call
  end

  it 'puts the conversation into the queue: class priority and label, clocks running' do
    reconcile(at: started_at + 5.minutes)

    expect(conversation.reload.priority).to eq('urgent')
    expect(conversation.label_list).to contain_exactly('vip')
    expect(account.labels.pluck(:title)).to include('vip')
    expect(tracker.reload).to have_attributes(priority_applied: 'urgent', labels_applied: ['vip'], fr_state: 'ok', nr_state: 'ok',
                                              res_state: 'ok', config_version: 7, active: true, fr_due_at: started_at + 30.minutes)
  end

  it 'never overrides a priority an operator set by hand' do
    reconcile(at: started_at + 1.minute)
    conversation.update!(priority: :low)
    reconcile(at: started_at + 2.minutes)

    expect(conversation.reload.priority).to eq('low')
    expect(tracker.reload.priority_manual).to be true

    contact.update!(custom_attributes: { 'segment_weight' => 'Mid Fish', 'segment_tier_90d' => 'Small' })
    reconcile(at: started_at + 3.minutes)
    expect(conversation.reload.priority).to eq('low')
    expect(tracker.reload.closed_reason).to eq('untracked')
  end

  it 'shadow mode (defaults): records the breach but adds no SLA labels, notes or alerts, even after flags flip later' do
    reconcile(at: started_at + 31.minutes)

    expect(tracker.reload).to have_attributes(fr_state: 'breached', fr_breached_at: started_at + 30.minutes)
    expect(conversation.reload.label_list).to contain_exactly('vip')
    expect(conversation.messages.where(private: true)).to be_empty

    loud = Care::Queue::Config.new(settings.merge('sla_labels_enabled' => true, 'alerts_enabled' => true), version: 8, source: 'test')
    reconcile(at: started_at + 32.minutes, with: loud)
    expect(conversation.reload.label_list).to contain_exactly('vip', 'sla-breach') # состояние видно, но старое нарушение не алертим
    expect(conversation.messages.where(private: true)).to be_empty
    expect(notifier).not_to have_received(:breach)
    expect(tracker.reload.config_version).to eq(8)
  end

  context 'with SLA labels and alerts enabled' do
    let(:overrides) { { 'sla_labels_enabled' => true, 'alerts_enabled' => true } }

    it 'marks risk, then breach exactly once: label, private note and alert; later ticks are idempotent' do
      reconcile(at: started_at + 25.minutes)
      expect(conversation.reload.label_list).to contain_exactly('vip', 'sla-risk')

      reconcile(at: started_at + 31.minutes)
      expect(conversation.reload.label_list).to contain_exactly('vip', 'sla-breach')
      notes = conversation.messages.where(private: true)
      expect(notes.count).to eq(1)
      expect(notes.first.content).to include('SLA VIP', '30 мин')
      expect(notifier).to have_received(:breach).once.with(hash_including(clock: :fr))

      reconcile(at: started_at + 40.minutes)
      expect(conversation.messages.where(private: true).count).to eq(1)
      expect(notifier).to have_received(:breach).once
    end

    it 'alerts per waiting episode for the next-response clock' do
      conversation.update_columns(first_reply_created_at: started_at + 10.minutes, waiting_since: started_at + 15.minutes) # rubocop:disable Rails/SkipsModelValidations
      reconcile(at: started_at + 76.minutes)
      expect(tracker.reload).to have_attributes(fr_state: 'met', nr_state: 'breached', nr_breached_anchor_at: started_at + 15.minutes)
      expect(notifier).to have_received(:breach).once.with(hash_including(clock: :nr))

      conversation.update_columns(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations
      reconcile(at: started_at + 80.minutes)
      expect(tracker.reload.nr_state).to eq('ok')
      expect(conversation.reload.label_list).to contain_exactly('vip', 'sla-breach') # нарушение остаётся в истории

      conversation.update_columns(waiting_since: started_at + 90.minutes) # rubocop:disable Rails/SkipsModelValidations
      reconcile(at: started_at + 151.minutes)
      expect(notifier).to have_received(:breach).twice
    end

    it 'does not alert for classes with alert_on_breach off, but still notes and labels' do
      contact.update!(custom_attributes: { 'segment_weight' => 'Big Fish', 'segment_tier_90d' => 'Small' })
      reconcile(at: started_at + 121.minutes)

      expect(tracker.reload).to have_attributes(class_key: 'big', fr_state: 'breached')
      expect(conversation.reload.priority).to eq('high')
      expect(conversation.label_list).to contain_exactly('sla-breach')
      expect(conversation.messages.where(private: true).count).to eq(1)
      expect(notifier).not_to have_received(:breach)
    end

    it 'closes the tracker on resolve, drops the risk label and keeps a breach label' do
      reconcile(at: started_at + 25.minutes)
      expect(conversation.reload.label_list).to include('sla-risk')

      conversation.resolved!
      reconcile(at: started_at + 26.minutes)
      expect(tracker.reload).to have_attributes(active: false, closed_reason: 'resolved', res_state: 'met', fr_state: 'ok')
      expect(tracker.resolved_at).to eq(started_at + 26.minutes)
      expect(conversation.reload.label_list).to contain_exactly('vip')
    end

    it 'escalates priority on breach when the class asks for it' do
      classes = settings['classes'].map do |c|
        c['key'] == 'vip' ? c.merge('chatwoot_priority' => 'high', 'escalate_priority_on_breach' => 'urgent') : c
      end
      escalating = Care::Queue::Config.new(settings.merge('classes' => classes), version: 9, source: 'test')

      reconcile(at: started_at + 5.minutes, with: escalating)
      expect(conversation.reload.priority).to eq('high')
      reconcile(at: started_at + 31.minutes, with: escalating)
      expect(conversation.reload.priority).to eq('urgent')
      expect(tracker.reload.priority_applied).to eq('urgent')
    end
  end

  it 'untracks when the contact leaves the queue: our label and priority go, tracker closes' do
    reconcile(at: started_at + 1.minute)
    contact.update!(custom_attributes: { 'segment_weight' => 'Mid Fish', 'segment_tier_90d' => 'Small' })
    reconcile(at: started_at + 2.minutes)

    expect(conversation.reload.priority).to be_nil
    expect(conversation.label_list).to be_empty
    expect(tracker.reload).to have_attributes(active: false, closed_reason: 'untracked', labels_applied: [], priority_applied: nil,
                                              config_version: 7)
  end

  it 'leaves labels that were there before us when untracking' do
    conversation.update_labels(['vip'])
    reconcile(at: started_at + 1.minute)
    expect(tracker.reload.labels_applied).to eq([]) # vip уже стоял — не наш

    contact.update!(custom_attributes: { 'segment_weight' => 'Mid Fish', 'segment_tier_90d' => 'Small' })
    reconcile(at: started_at + 2.minutes)
    expect(conversation.reload.label_list).to contain_exactly('vip')
  end

  it 're-derives states, priority and labels from a changed config on the next tick' do
    reconcile(at: started_at + 31.minutes)
    expect(tracker.reload.fr_state).to eq('breached')

    classes = settings['classes'].map { |c| c['key'] == 'vip' ? c.merge('first_response_minutes' => 60) : c }
    relaxed = Care::Queue::Config.new(settings.merge('classes' => classes), version: 8, source: 'test')
    reconcile(at: started_at + 32.minutes, with: relaxed)
    expect(tracker.reload).to have_attributes(fr_state: 'ok', fr_due_at: started_at + 60.minutes, config_version: 8)

    paused = Care::Queue::Config.new(settings.merge('queue_enabled' => false), version: 9, source: 'test')
    reconcile(at: started_at + 33.minutes, with: paused)
    expect(conversation.reload.priority).to be_nil
    expect(conversation.label_list).to be_empty
    expect(tracker.reload).to have_attributes(priority_applied: nil, labels_applied: [], active: true)

    reconcile(at: started_at + 34.minutes)
    expect(conversation.reload.priority).to eq('urgent')
    expect(conversation.label_list).to contain_exactly('vip')
  end
end
