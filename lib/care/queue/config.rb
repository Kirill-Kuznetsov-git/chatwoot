# Конфиг очередей и SLA по сегментам (SCC-102). Единый источник — Support Care
# (GET /api/segments/queue-config, меняется админом Care через PUT). Здесь: кэш в Redis на минуту,
# last-good копия без TTL на случай недоступности Care и встроенные дефолты как последний рубеж.
# Все решения (класс контакта, приоритет, лейблы, сроки) выводятся из текущего экземпляра на каждом тике,
# поэтому смена конфига в Care применяется ко всем открытым диалогам в течение минуты.
class Care::Queue::Config
  CACHE_KEY = 'care:queue_config:cache'.freeze
  LAST_GOOD_KEY = 'care:queue_config:last_good'.freeze
  CACHE_TTL_SECONDS = 60
  RISK_LABEL = 'sla-risk'.freeze
  BREACH_LABEL = 'sla-breach'.freeze

  # Класс очереди. Контакт попадает в класс, если его вес входит в weights ИЛИ tier входит в tiers.
  QueueClass = Struct.new(:key, :name, :weights, :tiers, :chatwoot_priority, :labels, :sla_enabled,
                          :first_response_minutes, :next_response_minutes, :resolution_minutes,
                          :alert_on_breach, :escalate_priority_on_breach, keyword_init: true) do
    def matches?(weight, tier)
      (weight.present? && weights.include?(weight)) || (tier.present? && tiers.include?(tier))
    end
  end

  attr_reader :version, :source, :classes, :risk_share, :queue_enabled, :sla_labels_enabled, :alerts_enabled,
              :digest_enabled, :digest_hour_utc, :kpi_first_response_minutes

  # source: cache | care | last_good | defaults — для логов и rake care:queue_config.
  def self.current(client: nil)
    body = read(CACHE_KEY, 'cache') || fetch(client) || read(LAST_GOOD_KEY, 'last_good')
    if body.nil?
      Rails.logger.warn('Care::Queue::Config: Care недоступен и нет last-good копии — работаем на встроенных дефолтах')
      body = { 'settings' => Care::Queue::Defaults::SETTINGS, 'version' => 0, 'source' => 'defaults' }
    end
    new(body['settings'], version: body['version'].to_i, source: body['source'])
  end

  def self.invalidate!
    Redis::Alfred.delete(CACHE_KEY)
  end

  def self.fetch(client)
    body = (client || Care::Client.new).queue_config
    json = { 'settings' => body['settings'], 'version' => body['version'].to_i }.to_json
    Redis::Alfred.setex(CACHE_KEY, json, CACHE_TTL_SECONDS)
    Redis::Alfred.set(LAST_GOOD_KEY, json)
    { 'settings' => body['settings'], 'version' => body['version'].to_i, 'source' => 'care' }
  rescue Care::Client::Error => e
    Rails.logger.warn("Care::Queue::Config: не удалось получить конфиг из Care (#{e.class}: #{e.message})")
    nil
  end

  def self.read(key, source)
    raw = Redis::Alfred.get(key)
    return nil if raw.blank?

    body = JSON.parse(raw)
    return nil unless body.is_a?(Hash) && body['settings'].is_a?(Hash)

    body.merge('source' => source)
  rescue JSON::ParserError
    nil
  end

  def initialize(settings, version: 0, source: 'defaults')
    settings = settings.to_h.with_indifferent_access
    @version = version
    @source = source
    @classes = Array(settings[:classes]).map { |raw| build_class(raw) }
    @risk_share = settings.fetch(:risk_share, 0.8).to_f
    @queue_enabled = settings.fetch(:queue_enabled, true) == true
    @sla_labels_enabled = settings.fetch(:sla_labels_enabled, false) == true
    @alerts_enabled = settings.fetch(:alerts_enabled, false) == true
    @digest_enabled = settings.fetch(:digest_enabled, true) == true
    @digest_hour_utc = settings.fetch(:digest_hour_utc, 6).to_i
    @kpi_first_response_minutes = settings.fetch(:kpi_first_response_minutes, 360).to_i
  end

  # Первый подходящий класс по порядку; nil — контакт вне очереди (нет сегмента или сегмент не ценный).
  def classify(contact)
    attrs = contact&.custom_attributes.to_h
    weight = attrs['segment_weight']
    tier = attrs['segment_tier_90d']
    return nil if weight.blank? && tier.blank?

    classes.find { |klass| klass.matches?(weight, tier) }
  end

  def class_for(key)
    classes.find { |klass| klass.key == key }
  end

  # SQL-условие «контакт попадает хоть в один класс» — для выборок без загрузки контактов в память.
  def contact_match_sql
    weights = classes.flat_map(&:weights).uniq
    tiers = classes.flat_map(&:tiers).uniq
    parts = []
    parts << ActiveRecord::Base.sanitize_sql_array(["contacts.custom_attributes->>'segment_weight' IN (?)", weights]) if weights.any?
    parts << ActiveRecord::Base.sanitize_sql_array(["contacts.custom_attributes->>'segment_tier_90d' IN (?)", tiers]) if tiers.any?
    parts.empty? ? '1 = 0' : parts.join(' OR ')
  end

  private

  def build_class(raw)
    raw = raw.to_h.with_indifferent_access
    QueueClass.new(**queue_fields(raw), **sla_fields(raw))
  end

  def queue_fields(raw)
    {
      key: raw[:key].to_s, name: raw[:name].presence || raw[:key].to_s,
      weights: Array(raw[:weights]).map(&:to_s), tiers: Array(raw[:tiers]).map(&:to_s),
      chatwoot_priority: raw[:chatwoot_priority].presence, labels: Array(raw[:labels]).map(&:to_s)
    }
  end

  def sla_fields(raw)
    {
      sla_enabled: raw.fetch(:sla_enabled, true) == true,
      first_response_minutes: raw[:first_response_minutes]&.to_i,
      next_response_minutes: raw[:next_response_minutes]&.to_i,
      resolution_minutes: raw[:resolution_minutes]&.to_i,
      alert_on_breach: raw.fetch(:alert_on_breach, false) == true,
      escalate_priority_on_breach: raw[:escalate_priority_on_breach].presence
    }
  end
end
