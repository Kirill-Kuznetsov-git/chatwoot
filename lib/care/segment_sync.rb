# Сегмент пользователя (SCC-67 / SCC-100). Support Care ночью считает Role × Weight за всё
# время и tier за 90 дней и отдаёт их по GET /api/users/{id}/segment. Chatwoot забирает сегмент
# по identifier контакта (= StarPets user_id, 24-hex) и кладёт в custom_attributes, чтобы
# оператор видел его в чате, а автоматизации и SLA могли на него опираться.
#
# Выключено по умолчанию. Включается тремя переменными окружения:
#   CARE_SEGMENT_SYNC_ENABLED=true, CARE_API_URL, CARE_SERVICE_KEY (сервисный ключ Care со
#   скоупом profile:read — только чтение). CARE_SEGMENT_SYNC_ACCOUNT_ID ограничивает аккаунт.
module Care::SegmentSync
  IDENTIFIER_RE = /\A[0-9a-f]{24}\z/
  FRESH_FOR = 24.hours
  VALUE_KEYS = %w[segment_role segment_weight segment_tier_90d segment_label segment_priority].freeze
  SYNCED_AT_KEY = 'segment_synced_at'.freeze

  def self.enabled?
    ENV.fetch('CARE_SEGMENT_SYNC_ENABLED', nil) == 'true' &&
      ENV.fetch('CARE_API_URL', nil).present? && ENV.fetch('CARE_SERVICE_KEY', nil).present?
  end

  def self.account_allowed?(account_id)
    allowed = ENV.fetch('CARE_SEGMENT_SYNC_ACCOUNT_ID', nil)
    allowed.blank? || allowed.to_i == account_id.to_i
  end

  def self.identifier_valid?(identifier)
    identifier.to_s.match?(IDENTIFIER_RE)
  end

  # Свежий сегмент не перезапрашиваем: он меняется раз в сутки.
  def self.fresh?(contact)
    synced_at = contact.custom_attributes.to_h[SYNCED_AT_KEY]
    return false if synced_at.blank?

    parsed = Time.zone.parse(synced_at.to_s)
    parsed.present? && parsed > FRESH_FOR.ago
  rescue ArgumentError
    false
  end

  # Ответ Care → значения атрибутов контакта. tier может быть nil (Newcomer) — ключ снимаем.
  def self.attributes_for(segment)
    {
      'segment_role' => segment['role'],
      'segment_weight' => segment['weight'],
      'segment_tier_90d' => segment['tier_90d'],
      'segment_label' => segment['label'],
      'segment_priority' => segment['priority_rank']
    }
  end

  # Полный цикл для одного контакта: сходить в Care и записать. Клиент подменяется в бэкфилле/тестах.
  def self.sync_contact!(contact, client: Care::Client.new)
    apply!(contact, attributes_for(client.segment(contact.identifier)))
  end

  # Пишет атрибуты. Если значения не изменились — только тихо обновляет метку времени
  # (update_columns, без событий), чтобы не гонять ActionCable и вебхуки на каждое обращение.
  # Возвращает true, если сегмент реально изменился.
  def self.apply!(contact, values, now: Time.current)
    current = contact.custom_attributes.to_h
    merged = current.merge(values.compact)
    merged.delete('segment_tier_90d') if values.key?('segment_tier_90d') && values['segment_tier_90d'].nil?
    merged[SYNCED_AT_KEY] = now.utc.iso8601

    changed = VALUE_KEYS.any? { |key| current[key] != merged[key] }
    if changed
      contact.update!(custom_attributes: merged)
    else
      contact.update_columns(custom_attributes: merged) # rubocop:disable Rails/SkipsModelValidations
    end
    changed
  end
end
