require 'rails_helper'

RSpec.describe Conversation do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, custom_attributes: { 'customer_field' => 'visible' }) }

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s, MANUAL_ESCALATION_LABEL: 'escalated',
                      MANUAL_ESCALATION_LINK_KEY: 'slack_thread_link') { example.run }
  end

  before { Current.reset }
  after { Current.reset }

  it 'blocks automatic resolution after a stale instance was loaded before the manual tag' do
    stale = described_class.find(conversation.id)
    conversation.update_labels(['escalated'])
    stale.resolved!
    expect(stale.reload.status).to eq('open')
  end

  it 'preserves a newer internal link when a stale instance attempts automatic resolution' do
    stale = described_class.find(conversation.id)
    conversation.update_labels(['escalated'])
    conversation.reload.update!(custom_attributes: conversation.custom_attributes.merge('slack_thread_link' => 'https://starpets.slack.com/thread'))
    stale.resolved!
    expect(stale.reload.custom_attributes['slack_thread_link']).to eq('https://starpets.slack.com/thread')
    expect(stale.status).to eq('open')
  end

  it 'keeps automatic pending transitions open for a manually escalated conversation' do
    conversation.update_labels(['escalated'])
    conversation.pending!
    expect(conversation.reload.status).to eq('open')
  end

  it 'allows a human operator to resolve the manual escalation' do
    conversation.update_labels(['escalated'])
    Current.user = create(:user)
    conversation.resolved!
    expect(conversation.reload.status).to eq('resolved')
  end

  it 'does not change accounts outside the explicit list' do
    conversation.update_labels(['escalated'])
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: '') { conversation.resolved! }
    expect(conversation.reload.status).to eq('resolved')
  end

  it 'leaves other inboxes unchanged when an inbox allowlist is configured' do
    with_modified_env(MANUAL_ESCALATION_INBOX_IDS: (conversation.inbox_id + 1).to_s) do
      conversation.update_labels(['escalated'])
      conversation.resolved!
    end
    expect(conversation.reload.status).to eq('resolved')
    expect(conversation.custom_attributes).not_to include('manual_escalation_hold')
  end

  it 'does not confuse the existing automatic L2 marker with the manual marker' do
    conversation.update_labels(['escalated_l2'])
    conversation.resolved!
    expect(conversation.reload.status).to eq('resolved')
  end

  it 'matches a configured label case insensitively' do
    conversation.update_labels(['custom-escalation'])
    with_modified_env(MANUAL_ESCALATION_LABEL: ' Custom-Escalation ') { conversation.resolved! }
    expect(conversation.reload.status).to eq('open')
  end

  it 'does not emit an auto-resolution message or change labels from cron' do
    account.update!(auto_resolve_after: 60, auto_resolve_message: 'Closed', auto_resolve_label: 'auto-resolved')
    conversation.update!(last_activity_at: 3.days.ago, label_list: ['escalated'])
    expect { Conversations::ResolutionJob.perform_now(account: account) }.not_to change(Message, :count)
    expect(conversation.reload.status).to eq('open')
    expect(conversation.label_list).to eq(['escalated'])
  end

  it 'blocks automation rule resolution even when a human triggered the rule' do
    conversation.update_labels(['escalated'])
    rule = create(:automation_rule, account: account, actions: [{ action_name: 'resolve_conversation', action_params: [] }])
    Current.user = create(:user)
    AutomationRules::ActionService.new(rule, account, conversation).perform
    expect(conversation.reload.status).to eq('open')
  end

  it 'keeps the internal hold after the manual tag is removed' do
    conversation.update_labels(['escalated'])
    conversation.update_labels([])
    conversation.resolved!
    expect(conversation.reload.status).to eq('open')
    expect(conversation.custom_attributes['manual_escalation_hold']).to be(true)
    expect(conversation.public_custom_attributes).not_to include('manual_escalation_hold')
  end

  it 'opens a pending conversation synchronously when the manual tag is applied' do
    conversation.pending!
    conversation.update_labels(['escalated'])
    expect(conversation.reload.status).to eq('open')
    expect(conversation.custom_attributes['manual_escalation_hold']).to be(true)
  end

  it 'hides only the configured internal attribute from customer payloads and Liquid email data' do
    conversation.update!(custom_attributes: { 'customer_field' => 'visible', 'slack_thread_link' => 'https://starpets.slack.com/private' })
    expect(conversation.public_custom_attributes).to eq('customer_field' => 'visible')
    expect(ConversationDrop.new(conversation).custom_attribute).to eq('customer_field' => 'visible')
    expect(conversation.push_event_data[:custom_attributes]).to include('slack_thread_link')
  end
end
