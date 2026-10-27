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

  it 'keeps title and reason private and protected even with all escalation flags disabled' do
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('manual_escalation_title' => 'Private title',
                                                                                 'manual_escalation_reason' => 'Другое'))
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: '', MANUAL_ESCALATION_DETAILS_ENABLED: 'false') do
      widget.inbox.update!(lock_to_single_conversation: true)
      post '/api/v1/widget/conversations', headers: { 'X-Auth-Token' => token },
                                           params: { website_token: widget.website_token, message: { content: 'Hello' } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('customer_field')
      expect(response.body).not_to include('Private title', 'manual_escalation_reason')
      expect(ConversationDrop.new(conversation).custom_attribute).to eq('customer_field' => 'visible')
      customer_params = { website_token: widget.website_token, custom_attributes: { manual_escalation_title: 'spoofed' } }
      post '/api/v1/widget/conversations/set_custom_attributes', headers: { 'X-Auth-Token' => token }, params: customer_params, as: :json
      expect(conversation.reload.custom_attributes).to include('manual_escalation_title' => 'Private title', 'manual_escalation_reason' => 'Другое')
    end
  end

  it 'keeps the author private in widget HTTP, Liquid and customer events even when disabled' do
    operator = create(:user, account: account, role: :administrator, name: 'PRIVATE-AUTHOR')
    fresh = create(:conversation, account: account, inbox: widget.inbox, contact: contact, contact_inbox: contact_inbox,
                                  custom_attributes: { 'customer_field' => 'visible' })
    Current.user = operator
    with_modified_env(MANUAL_ESCALATION_AUTHOR_ENABLED: 'true') { fresh.update_labels(['escalated']) }
    Current.reset
    fresh.reload
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: '', MANUAL_ESCALATION_DETAILS_ENABLED: 'false') do
      destroy_path = '/api/v1/widget/conversations/destroy_custom_attributes'
      customer_headers = { 'X-Auth-Token' => token }
      post destroy_path, headers: customer_headers,
                         params: { website_token: widget.website_token, custom_attribute: 'nonexistent' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('customer_field')
      expect(response.body).not_to include('PRIVATE-AUTHOR', 'manual_escalation_author')
      expect(ConversationDrop.new(fresh).custom_attribute).to eq('customer_field' => 'visible')
      clear_enqueued_jobs
      ActionCableListener.instance.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: fresh))
      customer_job = enqueued_jobs.find { |job| job[:job] == ActionCableBroadcastJob && job[:args][0].include?(contact_inbox.pubsub_token) }
      expect(customer_job[:args][2].to_json).not_to include('PRIVATE-AUTHOR', 'manual_escalation_author')
      customer_params = { website_token: widget.website_token, custom_attributes: { manual_escalation_author: { name: 'Spoof' } } }
      post '/api/v1/widget/conversations/set_custom_attributes', headers: customer_headers, params: customer_params, as: :json
      expect(fresh.reload.custom_attributes.dig('manual_escalation_author', 'name')).to eq('PRIVATE-AUTHOR')
      post destroy_path, headers: customer_headers,
                         params: { website_token: widget.website_token, custom_attribute: 'manual_escalation_author' }, as: :json
      expect(fresh.reload.custom_attributes.dig('manual_escalation_author', 'name')).to eq('PRIVATE-AUTHOR')
    end
  ensure
    Current.reset
  end
end
