# Auto-translates an INCOMING customer message into the handling operator's
# language and stores it in message.content_attributes.translations so the
# agent dashboard renders it automatically (useTranslations picks it up). The
# canonical content stays the original — the dashboard "View original" toggle
# still works. Outgoing (operator -> customer) translation is handled separately.
class AutoTranslateJob < ApplicationJob
  queue_as :medium

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.nil?

    conversation = message.conversation
    operator_locale = resolve_operator_locale(conversation)
    return if operator_locale.blank?

    translated = Integrations::Openai::TranslateService.new(
      account: message.account, content: message.content, target_language: operator_locale
    ).perform
    return if translated.blank? || translated.strip == message.content.to_s.strip

    translations = (message.content_attributes['translations'] || {}).merge(operator_locale => translated)
    message.update!(content_attributes: message.content_attributes.merge('translations' => translations))
  end

  private

  # The human agent's chosen UI language (so it matches the dashboard's
  # translation auto-select), falling back to the account default.
  def resolve_operator_locale(conversation)
    conversation.assignee&.ui_settings&.dig('locale').presence || conversation.account.locale
  end
end
