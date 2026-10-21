class ManualEscalations::WebhookJob < ApplicationJob
  queue_as :medium
  self.log_arguments = false
  retry_on Webhooks::Trigger::RetryableError, wait: :polynomially_longer, attempts: 10

  def perform(webhook_id, payload, delivery_id: nil)
    webhook = Webhook.find_by(id: webhook_id)
    return unless delivery_allowed?(webhook, payload)

    raise ArgumentError, 'Signed manual escalation delivery is required' if webhook.secret.blank? || delivery_id.blank?

    Webhooks::Trigger.execute(webhook.url, payload, :manual_escalation_webhook, secret: webhook.secret, delivery_id: delivery_id)
  rescue Webhooks::Trigger::RetryableError => e
    Rails.logger.warn("[ManualEscalations::WebhookJob] delivery=#{delivery_id} status=#{e.status}")
    raise
  end

  private

  def delivery_allowed?(webhook, payload)
    configured_webhook?(webhook) && matching_webhook_scope?(webhook, payload) &&
      Conversation.new(account_id: webhook.account_id, inbox_id: payload[:inbox_id]).manual_escalation_enabled? &&
      webhook.account.api_and_webhooks_enabled?
  end

  def configured_webhook?(webhook)
    webhook&.name == 'manual_escalation' &&
      ENV.fetch('MANUAL_ESCALATION_WEBHOOK_URLS', '').split(',').map(&:strip).include?(webhook.url) &&
      webhook.subscriptions.include?('conversation_updated')
  end

  def matching_webhook_scope?(webhook, payload)
    webhook.account_id.to_s == payload.dig(:account, :id).to_s &&
      (webhook.inbox_id.blank? || webhook.inbox_id.to_s == payload[:inbox_id].to_s)
  end
end
