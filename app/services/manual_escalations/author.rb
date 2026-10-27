class ManualEscalations::Author
  KEY = 'manual_escalation_author'.freeze
  SLACK_ID = /\A[UW][A-Z0-9]{8,20}\z/

  def initialize(conversation)
    @conversation = conversation
  end

  # Called under the conversation row lock, before the hold is first written.
  # Never trust an author supplied through custom attributes or backfill history.
  def sync!(persisted, operator:)
    attributes = (@conversation.custom_attributes || {}).except(KEY)
    previous = persisted&.custom_attributes || {}
    if previous.key?(KEY)
      attributes[KEY] = previous[KEY]
    elsif operator && first_escalation?(persisted, previous)
      attributes[KEY] = snapshot(operator)
    end
    @conversation.custom_attributes = attributes
  end

  def as_json(*)
    value = (@conversation.custom_attributes || {})[KEY]
    return unless valid_snapshot?(value)

    result = value.slice('id', 'name')
    result['slack_user_id'] = value['slack_user_id'] if value['slack_user_id'].is_a?(String) && SLACK_ID.match?(value['slack_user_id'])
    result
  end

  private

  def snapshot(operator)
    name = operator.name.to_s.gsub(/[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/, ' ').squish.first(150)
    result = { 'id' => operator.id, 'name' => name.presence || "Оператор Chatwoot ##{operator.id}" }
    slack_id = mapped_slack_id(operator.id)
    result['slack_user_id'] = slack_id if slack_id
    result
  end

  def valid_snapshot?(value)
    value.is_a?(Hash) && value['id'].is_a?(Integer) && value['id'].positive? && safe_name?(value['name'])
  end

  def safe_name?(name)
    name.is_a?(String) && name.present? && name.length <= 150 && !name.match?(/[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/)
  end

  def first_escalation?(persisted, previous)
    return false if previous.key?('manual_escalation_hold') || previous[@conversation.manual_escalation_link_key].present?
    return false if persisted&.manual_escalation_tagged?

    @conversation.label_list_changed? && @conversation.label_list.any? { |label| label.downcase == @conversation.manual_escalation_label }
  end

  def mapped_slack_id(user_id)
    mapping = JSON.parse(ENV.fetch('MANUAL_ESCALATION_SLACK_USERS', '{}'))
    account_mapping = mapping[@conversation.account_id.to_s] if mapping.is_a?(Hash)
    value = account_mapping[user_id.to_s] if account_mapping.is_a?(Hash)
    value if value.is_a?(String) && SLACK_ID.match?(value)
  rescue JSON::ParserError
    Rails.logger.warn('Invalid MANUAL_ESCALATION_SLACK_USERS; using operator names')
    nil
  end
end
