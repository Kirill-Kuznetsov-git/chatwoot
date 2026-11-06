class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  def perform
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }
    }
  end

  def base_relation
    conversations = @account.conversations.includes(
      :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :messages, :contact_inbox
    )

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account
    ).perform
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    @conversations.sort_on_last_activity_at.page(current_page)
  end

  private

  def handle_standard_attributes(current_filter, query_hash, current_index, filter_operator_value)
    key = { 'care_segment_weight' => 'segment_weight', 'care_segment_role' => 'segment_role' }[query_hash[:attribute_key]]
    return super unless key

    definition = Care::SegmentAttributeDefinitions::DEFINITIONS.find { |item| item[:key] == key }
    values = query_hash[:values]
    unless values.is_a?(Array) && values.present? && (values - definition[:values]).empty?
      raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: query_hash[:attribute_key])
    end

    @filter_values["value_#{current_index}"] = values
    @filter_values['care_account_id'] = @account.id
    membership = query_hash[:filter_operator] == 'equal_to' ? 'IN' : 'NOT IN'
    "conversations.contact_id #{membership} (SELECT contacts.id FROM contacts WHERE contacts.account_id = :care_account_id " \
      "AND (contacts.custom_attributes ? 'segment_weight' OR contacts.custom_attributes ? 'segment_role') " \
      "AND contacts.custom_attributes ->> '#{key}' IN (:value_#{current_index})) #{query_hash[:query_operator]}"
  end
end
