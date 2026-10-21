require 'rails_helper'

RSpec.describe 'Manual escalation customer privacy', type: :request do
  let(:account) { create(:account) }
  let(:widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: widget.inbox) }
  let(:url) { 'https://starpets.slack.com/archives/C0AMUJ61CGN/p1792660000000000' }
  let(:conversation) do
    create(:conversation, account: account, inbox: widget.inbox, contact: contact, contact_inbox: contact_inbox,
                          custom_attributes: { 'slack_thread_link' => url, 'customer_field' => 'visible' })
  end
  let(:token) { Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: widget.inbox.id }).generate_token }

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s) { example.run }
  end

  it 'filters internal fields from contact events while keeping them for operators' do
    admin = create(:user, account: account, role: :administrator)
    conversation
    clear_enqueued_jobs
    event = Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation)
    ActionCableListener.instance.conversation_updated(event)
    jobs = enqueued_jobs.select { |job| job[:job] == ActionCableBroadcastJob }
    customer_job = jobs.find { |job| job[:args][0].include?(contact_inbox.pubsub_token) }
    operator_job = jobs.find { |job| job[:args][0].include?(admin.pubsub_token) }
    expect(customer_job[:args][2].to_json).not_to include(url)
    expect(operator_job[:args][2].to_json).to include(url)
  end

  it 'filters internal fields from typing events sent to the customer' do
    admin = create(:user, account: account, role: :administrator)
    conversation
    clear_enqueued_jobs
    event = Events::Base.new(:'conversation.typing_on', Time.zone.now, conversation: conversation, user: admin)
    ActionCableListener.instance.conversation_typing_on(event)
    customer_job = enqueued_jobs.find { |job| job[:job] == ActionCableBroadcastJob && job[:args][0].include?(contact_inbox.pubsub_token) }
    expect(customer_job[:args][2].to_json).not_to include(url)
  end

  it 'keeps the stored link private and protected after the feature is disabled' do
    conversation
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: '') do
      expect(conversation.public_custom_attributes).not_to include('slack_thread_link')
      clear_enqueued_jobs
      event = Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation)
      ActionCableListener.instance.conversation_updated(event)
      customer_job = enqueued_jobs.find { |job| job[:job] == ActionCableBroadcastJob && job[:args][0].include?(contact_inbox.pubsub_token) }
      expect(customer_job[:args][2].to_json).not_to include(url)
      post '/api/v1/widget/conversations/set_custom_attributes',
           headers: { 'X-Auth-Token' => token },
           params: { website_token: widget.website_token, custom_attributes: { slack_thread_link: 'spoofed' } }, as: :json
      expect(conversation.reload.custom_attributes['slack_thread_link']).to eq(url)
    end
  end

  it 'prevents the widget from spoofing or deleting the internal link' do
    conversation
    post '/api/v1/widget/conversations/set_custom_attributes',
         headers: { 'X-Auth-Token' => token },
         params: { website_token: widget.website_token, custom_attributes: { slack_thread_link: 'spoofed', customer_field: 'updated' } }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(conversation.reload.custom_attributes).to eq('slack_thread_link' => url, 'customer_field' => 'updated')
    post '/api/v1/widget/conversations/destroy_custom_attributes',
         headers: { 'X-Auth-Token' => token },
         params: { website_token: widget.website_token, custom_attribute: 'slack_thread_link' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(url)
    expect(conversation.reload.custom_attributes['slack_thread_link']).to eq(url)
  end

  it 'does not show the private escalation note in a reused widget conversation' do
    conversation
    widget.inbox.update!(lock_to_single_conversation: true)
    create(:message, conversation: conversation, private: true, content: "Manual escalation: #{url}")
    post '/api/v1/widget/conversations',
         headers: { 'X-Auth-Token' => token },
         params: { website_token: widget.website_token, message: { content: 'Hello' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(url)
  end

  it 'does not show the private escalation note in the widget conversation list' do
    conversation
    create(:message, conversation: conversation, private: true, content: "Manual escalation: #{url}")
    get '/api/v1/widget/conversations/list_all', headers: { 'X-Auth-Token' => token },
                                                 params: { website_token: widget.website_token }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(url)
  end

  it 'does not include the internal link or private note in a customer email transcript' do
    create(:message, conversation: conversation, private: true, content: "Manual escalation: #{url}")
    mailer = ConversationReplyMailer.new
    allow(ConversationReplyMailer).to receive(:new).and_return(mailer)
    allow(mailer).to receive(:smtp_config_set_or_development?).and_return(true)
    mail = ConversationReplyMailer.conversation_transcript(conversation, 'customer@example.com')
    expect(mail.body.encoded).not_to include(url)
  end

  it 'does not expose private notes or accept an internal link through the public API' do
    channel = create(:channel_api, account: account)
    api_contact_inbox = create(:contact_inbox, contact: contact, inbox: channel.inbox)
    api_conversation = create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: api_contact_inbox)
    create(:message, conversation: api_conversation, private: true, content: "Manual escalation: #{url}")
    base = "/public/api/v1/inboxes/#{channel.identifier}/contacts/#{api_contact_inbox.source_id}/conversations"
    get "#{base}/#{api_conversation.display_id}", as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(url)
    post base, params: { custom_attributes: { slack_thread_link: url, customer_field: 'ok' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(channel.inbox.conversations.last.custom_attributes).to eq('customer_field' => 'ok')
  end

  it 'does not let widget clients apply the operator-only manual escalation label' do
    create(:label, account: account, title: 'escalated')
    post '/api/v1/widget/messages', headers: { 'X-Auth-Token' => token },
                                    params: { website_token: widget.website_token, message: { content: 'Hello' }, labels: ['escalated'] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contact_inbox.conversations.last.label_list).not_to include('escalated')
    expect(contact_inbox.conversations.last.custom_attributes).not_to include('manual_escalation_hold')
  end
end
