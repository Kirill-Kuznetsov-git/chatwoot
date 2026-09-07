# Алерты лиду о просрочках SLA и ежедневный дайджест — Slack incoming webhook из CARE_SLA_SLACK_WEBHOOK_URL.
# Без URL всё уходит в лог (тихий режим). Ошибки Slack не должны валить тик — только лог.
module Care::Sla::Notifier
  ENV_KEY = 'CARE_SLA_SLACK_WEBHOOK_URL'.freeze
  TIMEOUT_SECONDS = 5

  def self.enabled?
    ENV.fetch(ENV_KEY, nil).present?
  end

  def self.breach(conversation:, klass:, clock:, text:)
    segment = conversation.contact&.custom_attributes.to_h['segment_label']
    post("#{text}\n#{segment.presence || klass.name} · #{conversation_url(conversation)}", kind: "breach:#{clock}")
  end

  def self.digest(text)
    post(text, kind: 'digest')
  end

  def self.post(text, kind:)
    url = ENV.fetch(ENV_KEY, nil)
    if url.blank?
      Rails.logger.info("Care::Sla::Notifier[#{kind}] (webhook не задан): #{text}")
      return false
    end

    response = HTTParty.post(url, body: { text: text }.to_json, headers: { 'Content-Type' => 'application/json' },
                                  timeout: TIMEOUT_SECONDS)
    Rails.logger.warn("Care::Sla::Notifier[#{kind}]: Slack HTTP #{response.code}") unless response.success?
    response.success?
  rescue StandardError => e
    Rails.logger.warn("Care::Sla::Notifier[#{kind}]: #{e.class}: #{e.message}")
    false
  end

  def self.conversation_url(conversation)
    "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end
end
