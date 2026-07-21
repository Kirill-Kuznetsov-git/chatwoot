# Auto-translates an OUTGOING operator message into the customer's language and
# stores it in message.content_attributes.translations so the widget renders the
# translation instead of the original (the operator dashboard keeps showing the
# original content). Mirrors AutoTranslateJob (incoming) but targets the
# customer's front-end language. Skips when the customer language is unknown.
class OutgoingAutoTranslateJob < ApplicationJob
  queue_as :medium

  # Retry transient OpenAI failures (rate limit / 5xx / network); after attempts
  # are exhausted, give up quietly (the widget falls back to the original).
  retry_on Integrations::Openai::TranslateService::TransientError, wait: :polynomially_longer, attempts: 5 do |_job, error|
    Rails.logger.error("[OutgoingAutoTranslate] gave up after retries: #{error.message}")
  end

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.nil?

    customer_locale = resolve_customer_locale(message.conversation)
    return if customer_locale.blank?
    return if message.content_attributes.dig('translations', customer_locale).present?

    translated = Integrations::Openai::TranslateService.new(
      account: message.account, content: message.content, target_language: customer_locale
    ).perform
    return if translated.blank? || translated.strip == message.content.to_s.strip

    translations = (message.content_attributes['translations'] || {}).merge(customer_locale => translated)
    message.update!(content_attributes: message.content_attributes.merge('translations' => translations))
  end

  private

  # The customer's language, by priority:
  #   1) front-end chosen language (contact custom attribute 'language') — exact,
  #      matches the widget render locale; ~96% of widget conversations.
  #   2) browser Accept-Language (conversation.additional_attributes.browser_language)
  #      — fallback when the front-end language wasn't recorded (~the rest).
  #   3) 'en' default — if neither is known, translate to English (lingua franca)
  #      rather than leaving the operator's message untranslated.
  # Returns the normalized base code (e.g. 'pt-BR' -> 'pt').
  def resolve_customer_locale(conversation)
    lang = conversation.contact&.custom_attributes&.dig('language').presence ||
           conversation.additional_attributes&.dig('browser_language').presence
    (lang&.to_s&.split(/[-_]/)&.first&.downcase).presence || 'en'
  end
end
