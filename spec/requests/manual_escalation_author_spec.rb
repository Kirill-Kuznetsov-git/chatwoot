require 'rails_helper'

RSpec.describe 'Manual escalation author', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent, name: 'Actual operator') }
  let(:assignee) { create(:user, account: account, role: :agent, name: 'Other assignee') }
  let(:conversation) { create(:conversation, account: account, assignee: assignee) }
  let(:headers) { user.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/manual_escalation_details" }
  let(:mapping) { { account.id.to_s => { user.id.to_s => 'U012ABC3456' } }.to_json }

  before do
    Current.reset
    create(:inbox_member, user: user, inbox: conversation.inbox)
  end

  after { Current.reset }

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s, MANUAL_ESCALATION_DETAILS_ENABLED: 'true',
                      MANUAL_ESCALATION_AUTHOR_ENABLED: 'true', MANUAL_ESCALATION_SLACK_USERS: mapping) { example.run }
  end

  it 'records the authenticated operator rather than the assignee at confirmation' do
    post path, headers: headers, params: { title: 'Title', reason: '', escalate: true,
                                           author: { id: assignee.id, name: 'Spoof', slack_user_id: 'UATTACK' } }, as: :json
    expect(response).to have_http_status(:ok)
    expected = { 'id' => user.id, 'name' => 'Actual operator', 'slack_user_id' => 'U012ABC3456' }
    expect(conversation.reload.custom_attributes['manual_escalation_author']).to eq(expected)
    expect(response.parsed_body['author']).to eq(expected)
    expect(response.parsed_body['author'].keys).not_to include('email')
  end

  it 'keeps the first author through edits, reassignment and repeated confirmation' do
    post path, headers: headers, params: { title: 'First', reason: '', escalate: true }, as: :json
    original = conversation.reload.custom_attributes['manual_escalation_author']
    expect(original).to be_present
    Current.user = assignee
    conversation.update!(assignee: user)
    create(:inbox_member, user: assignee, inbox: conversation.inbox)
    post path, headers: assignee.create_new_auth_token, params: { title: 'Edited', reason: 'Другое', escalate: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.custom_attributes['manual_escalation_author']).to eq(original)
    native = path.sub('/manual_escalation_details', '/custom_attributes')
    post native, headers: headers, params: { custom_attributes: { manual_escalation_author: { name: 'Spoof' } } }, as: :json
    expect(conversation.reload.custom_attributes['manual_escalation_author']).to eq(original)
    post native, headers: headers, params: { custom_attributes: {} }, as: :json
    expect(conversation.reload.custom_attributes['manual_escalation_author']).to eq(original)
  end

  it 'does not attribute drafts, title edits or existing escalations retrospectively' do
    post path, headers: headers, params: { title: 'Draft', reason: '', escalate: false }, as: :json
    expect(conversation.reload.custom_attributes).not_to have_key('manual_escalation_author')
    Current.reset
    conversation.update_labels(['escalated'])
    post path, headers: headers, params: { title: 'Old ticket', reason: '', escalate: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.custom_attributes).not_to have_key('manual_escalation_author')
    expect(response.parsed_body['author']).to be_nil
  end

  it 'captures native human label transitions but not bots or automation rules' do
    Current.user = user
    conversation.update_labels(['escalated'])
    expect(conversation.reload.custom_attributes.dig('manual_escalation_author', 'id')).to eq(user.id)
    other = create(:conversation, account: account)
    Current.executed_by = create(:automation_rule, account: account)
    other.update_labels(['escalated'])
    expect(other.reload.custom_attributes).not_to have_key('manual_escalation_author')
  end

  it 'normalizes the display name and uses plain text when no valid account-scoped mapping exists' do
    user.update!(name: "  Actual\n operator  ")
    with_modified_env(MANUAL_ESCALATION_SLACK_USERS: { 'other-account' => { user.id.to_s => 'U012ABC3456' } }.to_json) do
      post path, headers: headers, params: { title: 'Title', reason: '', escalate: true }, as: :json
    end
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['author']).to eq('id' => user.id, 'name' => 'Actual operator')
  end

  it 'does not let a bot overwrite or fabricate the author through generic attributes' do
    post path, headers: headers, params: { title: 'Title', reason: '', escalate: true }, as: :json
    original = conversation.reload.custom_attributes['manual_escalation_author']
    bot = create(:agent_bot, account: account)
    native_path = path.sub('/manual_escalation_details', '/custom_attributes')
    post native_path, headers: { api_access_token: bot.access_token.token },
                      params: { custom_attributes: { manual_escalation_author: { id: 1, name: 'Spoof' } } }, as: :json
    expect(conversation.reload.custom_attributes['manual_escalation_author']).to eq(original)
  end

  it 'keeps identity after removing the label and releasing the hold' do
    post path, headers: headers, params: { title: 'Title', reason: '', escalate: true }, as: :json
    original = conversation.reload.custom_attributes['manual_escalation_author']
    Current.user = user
    conversation.update_labels([])
    conversation.manual_escalation_release_requested = true
    conversation.update!(status: :pending)
    Current.user = assignee
    conversation.update_labels(['escalated'])
    expect(conversation.reload.custom_attributes['manual_escalation_author']).to eq(original)
  end

  it 'never backfills a legacy thread even after its label is removed and reapplied' do
    Current.reset
    conversation.update_labels(['escalated'])
    conversation.update_labels([])
    Current.user = user
    conversation.update_labels(['escalated'])
    expect(conversation.reload.custom_attributes).not_to have_key('manual_escalation_author')
  end

  it 'fails validation without committing an author or a label' do
    post path, headers: headers, params: { title: 'x' * 151, reason: '', escalate: true }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.reload.custom_attributes).not_to have_key('manual_escalation_author')
    expect(conversation.label_list).to be_empty
  end

  it 'uses a safe plain name with invalid or absent optional Slack configuration' do
    ['{invalid', '[]', 'null', { account.id.to_s => { user.id.to_s => '<!channel>' } }.to_json].each do |config|
      with_modified_env(MANUAL_ESCALATION_SLACK_USERS: config) do
        fresh = create(:conversation, account: account)
        Current.user = user
        fresh.update_labels(['escalated'])
        expect(ManualEscalations::Details.new(fresh).as_json[:author]).to eq('id' => user.id, 'name' => user.name)
      end
    end
  end

  it 'allows escalation without capturing authors until all privacy-aware processes are deployed' do
    with_modified_env(MANUAL_ESCALATION_AUTHOR_ENABLED: 'false') do
      post path, headers: headers, params: { title: 'Title', reason: '', escalate: true }, as: :json
    end
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.label_list).to include('escalated')
    expect(conversation.custom_attributes).not_to have_key('manual_escalation_author')
  end

  it 'keeps existing author metadata immutable when capture is disabled for rollback' do
    post path, headers: headers, params: { title: 'Title', reason: '', escalate: true }, as: :json
    original = conversation.reload.custom_attributes['manual_escalation_author']
    with_modified_env(MANUAL_ESCALATION_AUTHOR_ENABLED: 'false') do
      native_path = path.sub('/manual_escalation_details', '/custom_attributes')
      post native_path, headers: headers, params: { custom_attributes: { manual_escalation_author: { name: 'Spoof' } } }, as: :json
      expect(conversation.reload.custom_attributes['manual_escalation_author']).to eq(original)
    end
  end
end
