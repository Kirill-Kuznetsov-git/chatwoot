require 'rails_helper'

RSpec.describe 'Manual escalation details', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, custom_attributes: { 'customer_field' => 'kept' }) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:headers) { user.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/manual_escalation_details" }

  before { create(:inbox_member, user: user, inbox: conversation.inbox) }

  around do |example|
    with_modified_env(MANUAL_ESCALATION_ACCOUNT_IDS: account.id.to_s, MANUAL_ESCALATION_DETAILS_ENABLED: 'true') { example.run }
  end

  it 'provides a safe fallback and optional reasons to an ordinary agent' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('enabled' => true, 'title' => 'Обращение требует проверки', 'title_override' => '',
                                            'reason' => '', 'max_length' => 150)
    expect(response.parsed_body['reasons']).to include('Другое')
  end

  it 'uses the account native reason list when installed' do
    create(:custom_attribute_definition, account: account, attribute_key: 'manual_escalation_reason',
                                         attribute_model: :conversation_attribute, attribute_display_type: :list, attribute_values: ['Новая причина'])
    get path, headers: headers
    expect(response.parsed_body['reasons']).to eq(['Новая причина'])
  end

  it 'confirms the metadata and escalation together while preserving labels and attributes' do
    conversation.update_labels(['known'])
    post path, headers: headers, params: { title: '  Проверить покупку  ', reason: 'Другое', escalate: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.label_list).to contain_exactly('known', 'escalated')
    expect(conversation.custom_attributes).to include('customer_field' => 'kept', 'manual_escalation_title' => 'Проверить покупку',
                                                      'manual_escalation_reason' => 'Другое', 'manual_escalation_hold' => true)
    expect(response.parsed_body).to include('title' => 'Проверить покупку', 'title_override' => 'Проверить покупку')
  end

  it 'does not reopen a resolved conversation when metadata is edited' do
    conversation.update_labels(['escalated'])
    Current.user = user
    conversation.update!(status: :resolved)
    post path, headers: headers, params: { title: '', reason: 'Другое', escalate: false }, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload).to be_resolved
    expect(response.parsed_body['title_override']).to eq('')
  end

  it 'validates all input before setting the tag' do
    valid_values = { escalate: true }
    [{ title: 'x' * 151, reason: '' }, { title: "a\nb", reason: '' }, { title: [], reason: '' },
     { title: '', reason: 'not allowed' }, { title: '', reason: '', escalate: 'true' }].each do |values|
      post path, headers: headers, params: valid_values.merge(values), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.reload.label_list).to be_empty
      expect(conversation.custom_attributes).to eq('customer_field' => 'kept')
    end
  end

  it 'accepts 150 Unicode characters and clearing restores the automatic title' do
    post path, headers: headers, params: { title: '🦊' * 150, reason: '', escalate: false }, as: :json
    expect(response).to have_http_status(:ok)
    post path, headers: headers, params: { title: ' ', reason: '', escalate: false }, as: :json
    expect(response.parsed_body).to include('title' => 'Обращение требует проверки', 'title_override' => '')
  end

  it 'allows bot reads but forbids bot writes including native fields' do
    bot = create(:agent_bot, account: account)
    bot_headers = { api_access_token: bot.access_token.token }
    get path, headers: bot_headers
    expect(response).to have_http_status(:ok)
    post path, headers: bot_headers, params: { title: 'spoof', reason: '', escalate: true }, as: :json
    expect(response).to have_http_status(:forbidden)
    post path.sub('/manual_escalation_details', '/custom_attributes'), headers: bot_headers,
                                                                       params: { custom_attributes: { manual_escalation_title: 'spoof' } }, as: :json
    expect(conversation.reload.custom_attributes).not_to include('manual_escalation_title')
  end

  it 'sanitizes native edits and permits deleting the override without deleting private hold fields' do
    post path, headers: headers, params: { title: 'Manual', reason: 'Другое', escalate: true }, as: :json
    native_path = path.sub('/manual_escalation_details', '/custom_attributes')
    post native_path, headers: headers, params: { custom_attributes: { manual_escalation_title: '  Edited  ', manual_escalation_reason: 'Другое' } },
                      as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.custom_attributes).to include('manual_escalation_title' => 'Edited', 'manual_escalation_hold' => true)
    post native_path, headers: headers, params: { custom_attributes: { manual_escalation_reason: 'Другое' } }, as: :json
    expect(conversation.reload.custom_attributes).not_to include('manual_escalation_title')
    expect(conversation.custom_attributes['manual_escalation_hold']).to be(true)
    post native_path, headers: headers, params: { custom_attributes: { manual_escalation_title: 'x' * 151 } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'returns disabled outside the scope or when the flag is off, and rejects writes' do
    [{ MANUAL_ESCALATION_DETAILS_ENABLED: 'false' }, { MANUAL_ESCALATION_INBOX_IDS: '0' }].each do |env|
      with_modified_env(env) do
        get path, headers: headers
        expect(response.parsed_body['enabled']).to be(false)
        post path, headers: headers, params: { title: '', reason: '', escalate: true }, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  it 'derives only allowlisted taxonomy pairs and preserves manual priority' do
    conversation.update_labels(%w[swap_trade questions])
    get path, headers: headers
    expect(response.parsed_body['title']).to eq('Вопрос об обмене')
    conversation.update_labels(%w[activities questions])
    get path, headers: headers
    expect(response.parsed_body['title']).to eq('Вопрос об активностях')
    post path, headers: headers, params: { title: 'Manual', reason: '', escalate: false }, as: :json
    conversation.update_labels(%w[psp deposit])
    get path, headers: headers
    expect(response.parsed_body['title']).to eq('Manual')
    post path, headers: headers, params: { title: '', reason: '', escalate: false }, as: :json
    expect(response.parsed_body['title']).to eq('Пополнение баланса')
    conversation.update_labels(['unknown-private-label'])
    get path, headers: headers
    expect(response.parsed_body['title']).to eq('Обращение требует проверки')
  end

  it 'does not reactivate a released pending conversation on native metadata edits' do
    conversation.update_labels(['escalated'])
    conversation.update_labels([])
    Current.user = user
    conversation.manual_escalation_release_requested = true
    conversation.update!(status: :pending)
    post path.sub('/manual_escalation_details', '/custom_attributes'), headers: headers,
                                                                       params: { custom_attributes: { manual_escalation_title: 'After release' } },
                                                                       as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.reload).to be_pending
    expect(conversation.custom_attributes['manual_escalation_hold']).to be(false)
    expect(conversation.label_list).to be_empty
  end

  it 'rejects bidi and control titles, permits emoji joiners, and filters unsafe dictionary values' do
    ["Unsafe\u202Etitle", "Unsafe\u0000title"].each do |title|
      post path, headers: headers, params: { title: title, reason: '', escalate: false }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    post path, headers: headers, params: { title: "👨\u200D👩\u200D👧", reason: '', escalate: false }, as: :json
    expect(response).to have_http_status(:ok)
    create(:custom_attribute_definition, account: account, attribute_key: 'manual_escalation_reason',
                                         attribute_model: :conversation_attribute, attribute_display_type: :list,
                                         attribute_values: ['Safe', 'x' * 101, "Unsafe\u202Ereason", 5, ''])
    get path, headers: headers
    expect(response.parsed_body['reasons']).to eq(['Safe'])
    post path, headers: headers, params: { title: '', reason: 'x' * 101, escalate: true }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.reload.label_list).to be_empty
  end

  it 'serves safe defaults for corrupted stored values without rewriting the record' do
    # Simulate legacy/corrupted storage which cannot pass current validation.
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_columns(custom_attributes: { 'manual_escalation_title' => "Unsafe\u202Etitle",
                                                     'manual_escalation_reason' => 'Removed option' })
    # rubocop:enable Rails/SkipsModelValidations
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('title' => 'Обращение требует проверки', 'title_override' => '', 'reason' => '')
    expect(conversation.reload.custom_attributes['manual_escalation_reason']).to eq('Removed option')
  end
end
