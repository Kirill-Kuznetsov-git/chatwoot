require 'rails_helper'

RSpec.describe SendReplyJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:bot_message) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, sender: bot, message_type: :outgoing)
  end

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s) { example.run }
  end

  it 'does not externally deliver a bot reply queued before the manual tag' do
    bot_message
    conversation.update_labels(['escalated'])
    expect(Messages::SendEmailNotificationService).not_to receive(:new)
    described_class.perform_now(bot_message.id)
  end

  it 'continues to deliver a human reply while the hold is active' do
    conversation.update_labels(['escalated'])
    human = create(:user, account: account)
    message = create(:message, conversation: conversation, account: account, inbox: conversation.inbox, sender: human, message_type: :outgoing)
    service = instance_double(Messages::SendEmailNotificationService, perform: nil)
    expect(Messages::SendEmailNotificationService).to receive(:new).with(message: message).and_return(service)
    described_class.perform_now(message.id)
  end
end
