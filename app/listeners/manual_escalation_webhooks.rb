module ManualEscalationWebhooks
  extend ActiveSupport::Concern

  private

  def conversation_webhook_changed_attributes(event)
    changes = extract_changed_attributes(event)
    changes&.each do |change|
      values = change.transform_keys(&:to_s)['custom_attributes']
      values&.transform_values! { |value| without_escalation_details(value) }
    end
    changes
  end

  def without_escalation_details(value)
    return value unless value.is_a?(Hash)

    keys = ManualEscalations::Details::PRIVATE_KEYS
    value.except(*keys, *keys.map(&:to_sym))
  end

  def manual_escalation_webhook_urls
    ENV.fetch('MANUAL_ESCALATION_WEBHOOK_URLS', '').split(',').map(&:strip)
  end

  def reserved_manual_escalation_webhook?(webhook)
    webhook.name == 'manual_escalation' || manual_escalation_webhook_urls.include?(webhook.url)
  end

  def deliver_manual_escalation_webhooks(conversation)
    return unless manual_escalation_delivery_active?(conversation)

    conversation.account.webhooks.account_type.each do |webhook|
      next unless configured_manual_escalation_webhook?(webhook)
      next if webhook.inbox_id.present? && webhook.inbox_id != conversation.inbox_id

      raise ArgumentError, 'Manual escalation webhook secret is missing' if webhook.secret.blank?

      ManualEscalations::WebhookJob.perform_later(
        webhook.id, manual_escalation_webhook_payload(conversation), delivery_id: SecureRandom.uuid
      )
    end
  end

  def manual_escalation_delivery_active?(conversation)
    conversation.manual_escalation_enabled? && conversation.account.api_and_webhooks_enabled? &&
      (conversation.custom_attributes&.key?('manual_escalation_hold') || conversation.manual_escalation_tagged?)
  end

  def configured_manual_escalation_webhook?(webhook)
    webhook.name == 'manual_escalation' && manual_escalation_webhook_urls.include?(webhook.url) &&
      webhook.subscriptions.include?('conversation_updated')
  end

  def manual_escalation_webhook_payload(conversation)
    {
      event: 'conversation_updated', id: conversation.display_id, account: { id: conversation.account_id },
      inbox_id: conversation.inbox_id, labels: conversation.label_list, status: conversation.status,
      custom_attributes: { manual_escalation_hold: conversation.custom_attributes&.[]('manual_escalation_hold') == true }
    }
  end
end
