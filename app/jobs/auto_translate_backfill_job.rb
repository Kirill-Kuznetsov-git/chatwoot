# Backfills auto-translation for a conversation's incoming customer messages
# when a human operator is assigned. Messages that arrived before the
# assignment (while the conversation was pending / bot-handled) are skipped by
# the message_created listener, so we translate them here on hand-off to a human.
class AutoTranslateBackfillJob < ApplicationJob
  queue_as :medium

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil? || conversation.assignee_id.blank?

    locale = operator_locale(conversation)
    return if locale.blank?

    conversation.messages.incoming.where(private: false).where.not(content: [nil, '']).find_each do |message|
      next if message.content_attributes.dig('translations', locale).present?

      AutoTranslateJob.perform_later(message.id)
    end
  end

  private

  # Matches AutoTranslateJob: the assigned human agent's UI language, falling
  # back to the account default.
  def operator_locale(conversation)
    conversation.assignee&.ui_settings&.dig('locale').presence || conversation.account.locale
  end
end
