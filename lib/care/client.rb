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
    response = HTTParty.get(
      "#{@base_url}/api/users/#{user_id}/segment",
      headers: { 'Authorization' => "Bearer #{@key}", 'Accept' => 'application/json' },
      timeout: TIMEOUT_SECONDS
    )
    handle(response)
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, SocketError,
         OpenSSL::SSL::SSLError, HTTParty::Error => e
    raise Unavailable, "care: #{e.class}"
  end

  private

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
    raise Error, 'care: unexpected body' unless body.is_a?(Hash) && body['role'].present? && body['weight'].present?

    body
  rescue JSON::ParserError
    raise Error, 'care: invalid JSON'
  end
end
