require 'rails_helper'

RSpec.describe AutomationRuleListener do
  let(:account) { create(:account) }
  let(:default_team) { create(:team, account: account) }
  let(:payment_team) { create(:team, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :open) }

  before do
    create(:automation_rule, account: account, event_name: 'conversation_opened',
                             conditions: [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['handover-ready'] }],
                             actions: [{ 'action_name' => 'assign_team_if_unassigned', 'action_params' => [default_team.id.to_s] }])
    create(:automation_rule, account: account, event_name: 'conversation_opened',
                             conditions: [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['payment'] }],
                             actions: [{ 'action_name' => 'assign_team', 'action_params' => [payment_team.id] }])
  end

  def open_event(conversation)
    event = Events::Base.new('conversation_opened', Time.zone.now, { conversation: conversation })
    described_class.instance.conversation_opened(event)
  end

  it 'assigns the fallback team to an ordinary conversation' do
    conversation.update_labels(['handover-ready'])
    open_event(conversation)
    expect(conversation.reload.team).to eq(default_team)
  end

  it 'does not assign the fallback when the payment rule matches even when the fallback was created first' do
    conversation.update_labels(%w[payment deposit handover-ready])
    allow(AutomationRules::ActionService).to receive(:new).and_call_original
    expect(AutomationRules::ActionService).not_to receive(:new).with(
      an_object_having_attributes(actions: [{ 'action_name' => 'assign_team_if_unassigned', 'action_params' => [default_team.id.to_s] }]),
      account, conversation
    )
    open_event(conversation)
    expect(conversation.reload.team).to eq(payment_team)
  end

  it 'selects the older matching fallback rule before the default route' do
    fallback, payment = account.automation_rules.order(:id).to_a
    fallback.update!(conditions: [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['payment'] }],
                     actions: [{ 'action_name' => 'assign_team_if_unassigned', 'action_params' => [payment_team.id] }])
    payment.update!(conditions: [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['handover-ready'] }],
                    actions: [{ 'action_name' => 'assign_team_if_unassigned', 'action_params' => [default_team.id] }])
    conversation.update_labels(%w[handover-ready payment deposit])

    open_event(conversation)

    expect(conversation.reload.team).to eq(payment_team)
  end

  it 'does not route conversations outside the configured handover' do
    open_event(conversation)
    expect(conversation.reload.team).to be_nil
  end

  it 'keeps a team already assigned to the ordinary conversation' do
    conversation.update_labels(['handover-ready'])
    conversation.update!(team: payment_team)
    open_event(conversation)
    expect(conversation.reload.team).to eq(payment_team)
  end
end
