# HTTP-клиент к Support Care. Единственная ручка — сегмент пользователя. Короткие таймауты:
# это фон (Sidekiq), но Care не должен становиться узким местом даже там.
class Care::Client
  class Error < StandardError; end
  # 401/403 — ключ не подходит, повторять бессмысленно
  class Unauthorized < Error; end
  # 5xx, таймаут, сеть — Sidekiq повторит
  class Unavailable < Error; end

  TIMEOUT_SECONDS = 5

  def initialize(base_url: ENV.fetch('CARE_API_URL'), key: ENV.fetch('CARE_SERVICE_KEY'))
    @base_url = base_url.to_s.chomp('/')
    @key = key
  end

  # => Hash с role/weight/tier_90d/label/priority_rank/source (см. Care segments_service.to_response)
  def segment(user_id)
    body = get("/api/users/#{user_id}/segment")
    raise Error, 'care: unexpected body' unless body['role'].present? && body['weight'].present?

    body
  end

  # Страница user_id, чей сегмент изменился в Care с момента since (после ночного пересчёта).
  # => { 'user_ids' => [...], 'next_after_id' => String|nil, 'total' => Integer, 'since' => String }
  def changed_user_ids(since:, after_id: nil, limit: 1000)
    query = { since: since.utc.iso8601, limit: limit }
    query[:after_id] = after_id if after_id.present?
    body = get('/api/segments/changed', query: query)
    raise Error, 'care: unexpected body' unless body['user_ids'].is_a?(Array)

    body
  end

  # Страница user_id ценных пользователей (киты и Big за 90 дней) для бэкфилла.
  # => { 'user_ids' => [...], 'next_after_id' => String|nil, 'total' => Integer, 'criteria' => {...} }
  def valuable_user_ids(after_id: nil, limit: 1000)
    query = { limit: limit }
    query[:after_id] = after_id if after_id.present?
    body = get('/api/segments/valuable', query: query)
    raise Error, 'care: unexpected body' unless body['user_ids'].is_a?(Array)

    body
  end

  # Конфиг очередей и SLA по сегментам (SCC-102), единый источник — Care.
  # => { 'settings' => { 'classes' => [...], флаги... }, 'version' => Integer, 'updated_at' => ..., 'updated_by' => ... }
  def queue_config
    body = get('/api/segments/queue-config')
    raise Error, 'care: unexpected body' unless body['settings'].is_a?(Hash) && body['settings']['classes'].is_a?(Array)

    body
  end

  private

  def get(path, query: nil)
    response = HTTParty.get(
      "#{@base_url}#{path}",
      headers: { 'Authorization' => "Bearer #{@key}", 'Accept' => 'application/json' },
      query: query, timeout: TIMEOUT_SECONDS
    )
    handle(response)
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, SocketError,
         OpenSSL::SSL::SSLError, HTTParty::Error => e
    raise Unavailable, "care: #{e.class}"
  end

  def handle(response)
    case response.code
    when 200 then parse(response)
    when 401, 403 then raise Unauthorized, "care: HTTP #{response.code}"
    when 400..499 then raise Error, "care: HTTP #{response.code}"
    else raise Unavailable, "care: HTTP #{response.code}"
    end
  end

  def parse(response)
    body = response.parsed_response
    body = JSON.parse(response.body) unless body.is_a?(Hash)
    raise Error, 'care: unexpected body' unless body.is_a?(Hash)

    body
  rescue JSON::ParserError
    raise Error, 'care: invalid JSON'
  end
end
