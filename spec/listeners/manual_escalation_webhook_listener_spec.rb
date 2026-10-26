require 'rails_helper'

RSpec.describe WebhookListener do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { 'https://example.com/webhooks/manual-escalation' }
  let!(:webhook) do
    create(:webhook, account: account, inbox_id: nil, name: 'manual_escalation', url: url,
                     subscriptions: %w[conversation_updated message_created])
  end

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s, MANUAL_ESCALATION_WEBHOOK_URLS: url) { example.run }
  end

  it 'sends only the minimal signed state payload to the dedicated hook' do
    conversation.update_labels(['escalated'])
    clear_enqueued_jobs
    described_class.instance.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation))
    job = enqueued_jobs.find { |entry| entry[:job] == ManualEscalations::WebhookJob }
    expect(job).to be_present
    expect(job[:args][0]).to eq(webhook.id)
    expect(ActiveJob::Arguments.deserialize(job[:args])[1]).to eq(
      event: 'conversation_updated', id: conversation.display_id, account: { id: account.id }, inbox_id: conversation.inbox_id,
      labels: ['escalated'], status: 'open', custom_attributes: { manual_escalation_hold: true }
    )
    expect(job[:args].to_json).not_to include('email', 'messages', 'sender', 'contact')
    expect(enqueued_jobs.none? { |entry| entry[:job] == WebhookJob }).to be(true)
  end

  it 'never falls back to generic customer data when feature flags are disabled' do
    conversation.update_labels(['escalated'])
    clear_enqueued_jobs
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: '', MANUAL_ESCALATION_WEBHOOK_URLS: '') do
      described_class.instance.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation))
    end
    expect(enqueued_jobs.select { |entry| [WebhookJob, ManualEscalations::WebhookJob].include?(entry[:job]) }).to be_empty
  end

  it 'does not send messages to the reserved hook even when subscribed' do
    message = create(:message, conversation: conversation, account: account, inbox: conversation.inbox)
    clear_enqueued_jobs
    described_class.instance.message_created(Events::Base.new(:'message.created', Time.zone.now, message: message))
    expect(enqueued_jobs.select { |entry| [WebhookJob, ManualEscalations::WebhookJob].include?(entry[:job]) }).to be_empty
  end

  it 'sends the explicit false hold marker needed for human release' do
    conversation.update!(status: :pending, custom_attributes: { 'manual_escalation_hold' => false })
    clear_enqueued_jobs
    described_class.instance.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation))
    job = enqueued_jobs.find { |entry| entry[:job] == ManualEscalations::WebhookJob }
    expect(ActiveJob::Arguments.deserialize(job[:args])[1]).to include(status: 'pending', custom_attributes: { manual_escalation_hold: false })
  end

  it 'keeps new private text out of both dedicated and generic webhook snapshots and changed attributes' do
    create(:webhook, account: account, inbox_id: nil, url: 'https://example.com/generic', subscriptions: ['conversation_updated'])
    conversation.update_labels(['escalated'])
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('manual_escalation_title' => 'PRIVATE-TITLE',
                                                                                 'manual_escalation_reason' => 'Другое'))
    clear_enqueued_jobs
    changes = { custom_attributes: [{ 'manual_escalation_title' => 'OLD-PRIVATE' }, conversation.custom_attributes] }
    event = Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation, changed_attributes: changes)
    described_class.instance.conversation_updated(event)
    jobs = enqueued_jobs.select { |entry| [WebhookJob, ManualEscalations::WebhookJob].include?(entry[:job]) }
    expect(jobs).to have_attributes(size: 2)
    expect(jobs.to_json).not_to include('PRIVATE-TITLE', 'OLD-PRIVATE', 'manual_escalation_reason')
  end
end
