class ManualEscalations::Details
  TITLE_KEY = 'manual_escalation_title'.freeze
  REASON_KEY = 'manual_escalation_reason'.freeze
  KEYS = [TITLE_KEY, REASON_KEY].freeze
  PRIVATE_KEYS = [*KEYS, ManualEscalations::Author::KEY].freeze
  MAX_LENGTH = 150
  DEFAULT_REASONS = ['Баг на сайте', 'Проблема при покупке', 'Проблема при продаже', 'Платёж или вывод', 'Другое'].freeze
  TOPICS = {
    %w[psp deposit] => 'Пополнение баланса', %w[psp cashout] => 'Вывод денег', %w[psp other] => 'Вопрос по балансу',
    %w[marketplace buy_item_manual] => 'Покупка предметов', %w[marketplace sale_item_manual] => 'Продажа предметов',
    %w[marketplace gp_rb_sp] => 'Robux и подарочные карты', %w[marketplace loyalty_program] => 'Программа лояльности',
    %w[bot bot_buy_question] => 'Покупка через бота', %w[bot bot_sale_question] => 'Продажа боту',
    %w[bot bot_buy_problem] => 'Проблема с покупкой у бота', %w[bot bot_sale_problem] => 'Проблема с продажей боту',
    %w[account authorization] => 'Вход в аккаунт', %w[account profile] => 'Профиль аккаунта',
    %w[account account_technical_glitches] => 'Техническая проблема', %w[account bugs] => 'Техническая проблема',
    %w[account security] => 'Безопасность аккаунта', %w[safety risks_and_bans] => 'Безопасность и блокировки',
    %w[swap_trade questions] => 'Вопрос об обмене', %w[swap_trade problems] => 'Проблема с обменом',
    %w[activities promo_codes] => 'Промокоды', %w[activities promo] => 'Промокоды',
    %w[activities competitions] => 'Конкурсы и награды', %w[activities cooperation] => 'Сотрудничество',
    %w[activities weekly_drop] => 'Еженедельный дроп', %w[activities referral] => 'Реферальная программа',
    %w[activities discord] => 'Discord', %w[activities questions] => 'Вопрос об активностях'
  }.freeze
  FALLBACK_TITLE = 'Обращение требует проверки'.freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def enabled?
    ENV.fetch('MANUAL_ESCALATION_DETAILS_ENABLED', 'false') == 'true' && @conversation.manual_escalation_enabled?
  end

  def reasons
    definition = @conversation.account.custom_attribute_definitions.find_by(attribute_key: REASON_KEY, attribute_model: :conversation_attribute)
    values = definition ? Array(definition.attribute_values) : DEFAULT_REASONS
    values.select { |value| safe_text?(value, 100) && value.present? && value == value.strip }
  end

  def as_json(*)
    attributes = @conversation.custom_attributes || {}
    override = attributes[TITLE_KEY]
    override = '' unless valid_title?(override) && override.is_a?(String)
    reason = attributes[REASON_KEY]
    reason = '' unless valid_reason?(reason) && reason.is_a?(String)
    { enabled: enabled?, title: override.presence || automatic_title, title_override: override,
      reason: reason, reasons: reasons, max_length: MAX_LENGTH, escalation_label: @conversation.manual_escalation_label,
      author: ManualEscalations::Author.new(@conversation).as_json }
  end

  def automatic_title
    labels = @conversation.label_list.map(&:downcase)
    matches = TOPICS.select { |pair, _title| pair.all? { |label| labels.include?(label) } }.values.uniq
    matches.one? ? matches.first : FALLBACK_TITLE
  end

  def update!(title:, reason:, escalate:)
    @conversation.with_lock do
      @conversation.custom_attributes = (@conversation.custom_attributes || {}).merge(TITLE_KEY => title, REASON_KEY => reason)
      @conversation.label_list = (@conversation.label_list + [@conversation.manual_escalation_label]).uniq if escalate
      @conversation.save!
    end
  end

  def normalize_attributes!
    attributes = @conversation.custom_attributes || {}
    attributes[TITLE_KEY] = attributes[TITLE_KEY].strip if attributes[TITLE_KEY].is_a?(String)
  end

  def changed?
    attributes = @conversation.custom_attributes || {}
    KEYS.any? { |name| attributes[name] != @conversation.custom_attributes_in_database&.[](name) }
  end

  def validate(attributes)
    errors = []
    errors << 'Title must be a single line of at most 150 characters' unless valid_title?(attributes[TITLE_KEY])
    errors << 'Reason must be selected from the allowed list' unless valid_reason?(attributes[REASON_KEY])
    errors
  end

  private

  def valid_title?(title)
    return true if title.nil?

    safe_text?(title, MAX_LENGTH)
  end

  def safe_text?(value, max_length)
    value.is_a?(String) && value.length <= max_length && !value.delete("\u200D").match?(/[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/)
  end

  def valid_reason?(reason)
    return true if reason.nil? || reason == ''

    reason.is_a?(String) && reasons.include?(reason)
  end
end
