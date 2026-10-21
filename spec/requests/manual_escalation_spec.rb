require 'rails_helper'

RSpec.describe 'Manual escalation API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, custom_attributes: { 'customer_field' => 'kept' }) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:headers) { { api_access_token: bot.access_token.token } }
  let(:url) { 'https://starpets.slack.com/archives/C0AMUJ61CGN/p1792660000000000' }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}" }

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s,
                      MANUAL_ESCALATION_SLACK_CHANNEL_ID: 'C0AMUJ61CGN') { example.run }
  end

  it 'merges the link atomically without replacing existing custom fields' do
    conversation
    expect do
      post "#{path}/manual_escalation_link", headers: headers, params: { url: url }, as: :json
    end.not_to change(conversation.messages, :count)
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.custom_attributes).to eq('customer_field' => 'kept', 'slack_thread_link' => url)
  end

  it 'deduplicates a private note across retries without sending public messages' do
    2.times do
      post "#{path}/manual_escalation_note", headers: headers, params: { event_id: 'event-123', url: url }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['private']).to be(true)
    end
    expect(conversation.messages.count).to eq(1)
    expect(conversation.messages.first).to have_attributes(private: true, content: include(url))
  end

  it 'preserves the link when ordinary custom attributes are replaced and prevents bypassing URL validation' do
    post "#{path}/manual_escalation_link", headers: headers, params: { url: url }, as: :json
    post "#{path}/custom_attributes", headers: headers,
                                      params: { custom_attributes: { slack_thread_link: 'https://example.org', customer_field: 'edited' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.custom_attributes).to eq('slack_thread_link' => url, 'customer_field' => 'edited')
  end

  it 'does not accept an unvalidated internal link through the account conversation create endpoint' do
    post "/api/v1/accounts/#{account.id}/conversations", headers: headers,
                                                         params: { inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
                                                                   custom_attributes: { slack_thread_link: url, customer_field: 'new' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.conversations.last.custom_attributes).to eq('customer_field' => 'new')
  end

  it 'rejects a different Slack channel before any write' do
    post "#{path}/manual_escalation_link", headers: headers, params: { url: url.sub('C0AMUJ61CGN', 'COTHER') }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.reload.custom_attributes).to eq('customer_field' => 'kept')
  end

  it 'rejects non-Slack URLs before any note is created' do
    post "#{path}/manual_escalation_note", headers: headers, params: { event_id: 'event-123', url: 'https://example.org' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.messages.count).to eq(0)
  end

  it 'rejects a regular agent' do
    user = create(:user, account: account, role: :agent)
    create(:inbox_member, user: user, inbox: conversation.inbox)
    post "#{path}/manual_escalation_link", headers: user.create_new_auth_token, params: { url: url }, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'allows an account administrator' do
    admin = create(:user, account: account, role: :administrator)
    post "#{path}/manual_escalation_link", headers: admin.create_new_auth_token, params: { url: url }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'rejects a bot belonging to a different account' do
    other_bot = create(:agent_bot, account: create(:account))
    post "#{path}/manual_escalation_link", headers: { api_access_token: other_bot.access_token.token }, params: { url: url }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(conversation.reload.custom_attributes).not_to include('slack_thread_link')
  end

  it 'rejects an empty idempotency identifier before creating a note' do
    post "#{path}/manual_escalation_note", headers: headers, params: { event_id: '', url: url }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.messages.count).to eq(0)
  end

  it 'rejects disabled accounts' do
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: '') do
      post "#{path}/manual_escalation_link", headers: headers, params: { url: url }, as: :json
    end
    expect(response).to have_http_status(:forbidden)
  end

  it 'returns the guarded current status to a queued bot resolve request' do
    conversation.update_labels(['escalated'])
    post "#{path}/toggle_status", headers: headers, params: { status: 'resolved' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'current_status')).to eq('open')
    expect(conversation.reload.status).to eq('open')
  end

  it 'rejects a public bot reply after manual escalation' do
    conversation.update_labels(['escalated'])
    post "#{path}/messages", headers: headers, params: { content: 'Late bot reply', message_type: 'outgoing', private: false }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.messages.where(content: 'Late bot reply')).to be_empty
  end

  it 'still accepts a private bot handover note during manual escalation' do
    conversation.update_labels(['escalated'])
    post "#{path}/messages", headers: headers, params: { content: 'Private handover', message_type: 'outgoing', private: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.messages.last).to have_attributes(private: true, content: 'Private handover')
  end

  it 'still accepts a human reply during manual escalation' do
    conversation.update_labels(['escalated'])
    admin = create(:user, account: account, role: :administrator)
    post "#{path}/messages", headers: admin.create_new_auth_token,
                             params: { content: 'Human reply', message_type: 'outgoing', private: false }, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.messages.last.content).to eq('Human reply')
  end

  it 'allows only an explicit human pending action without the tag to resume automation' do
    conversation.update_labels(['escalated'])
    conversation.update_labels([])
    post "#{path}/toggle_status", headers: headers, params: { status: 'pending' }, as: :json
    expect(conversation.reload.status).to eq('open')
    admin = create(:user, account: account, role: :administrator)
    post "#{path}/toggle_status", headers: admin.create_new_auth_token, params: { status: 'pending' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.status).to eq('pending')
    expect(conversation.custom_attributes['manual_escalation_hold']).to be(false)
    post "#{path}/messages", headers: headers, params: { content: 'Resumed reply', message_type: 'outgoing' }, as: :json
    expect(response).to have_http_status(:ok)
  end
end
