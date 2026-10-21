require 'rails_helper'

RSpec.describe ConversationReplyMailer do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:bot_message) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, sender: bot,
                     message_type: :outgoing, content: 'Late bot email')
  end

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s, SMTP_ADDRESS: 'smtp.test.invalid') { example.run }
  end

  before do
    ActionMailer::Base.deliveries.clear
  end

  it 'does not deliver an already queued bot email after escalation' do
    bot_message
    conversation.update_labels(['escalated'])
    described_class.reply_with_summary(conversation, bot_message.id).deliver_now
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'keeps a human reply while excluding bot content from the held email batch' do
    bot_message
    human = create(:user, account: account)
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, sender: human,
                     message_type: :outgoing, content: 'Human email response')
    conversation.update_labels(['escalated'])
    described_class.reply_with_summary(conversation, bot_message.id).deliver_now
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.last.body.decoded).to include('Human email response')
    expect(ActionMailer::Base.deliveries.last.body.decoded).not_to include('Late bot email')
  end

  it 'checks the hold again after rendering and before SMTP delivery' do
    mail = described_class.reply_with_summary(conversation, bot_message.id)
    mail.message
    conversation.update_labels(['escalated'])
    mail.deliver_now
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'requeues a human reply when escalation arrives after a mixed email was rendered' do
    bot_message
    human = create(:user, account: account)
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, sender: human,
                     message_type: :outgoing, content: 'Human response after bot')
    mail = described_class.reply_with_summary(conversation, bot_message.id)
    mail.message
    conversation.update_labels(['escalated'])
    clear_enqueued_jobs
    mail.deliver_now
    expect(ActionMailer::Base.deliveries).to be_empty
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.last.body.decoded).to include('Human response after bot')
    expect(ActionMailer::Base.deliveries.last.body.decoded).not_to include('Late bot email')
  end
end
