# Enqueues auto-translation of incoming customer messages into the operator's
# language. Gated OFF by default (AUTO_TRANSLATE_ENABLED) and only for
# human-handled conversations — bot/pending conversations are skipped because
# the AI agent already replies in the user's language. Two triggers:
#   - message_created: messages arriving after a human already owns the conv.
#   - assignee_changed: on hand-off to a human, back-fill earlier messages.
class AutoTranslateListener < BaseListener
  def message_created(event)
    return unless ENV['AUTO_TRANSLATE_ENABLED'] == 'true'

    message = extract_message_and_account(event)[0]
    return unless eligible?(message)

    AutoTranslateJob.perform_later(message.id)
  end

  # On hand-off to a human operator (assignee.changed), back-fill translations
  # for incoming messages that arrived before the assignment — message_created
  # skipped them because the conversation had no human assignee yet.
  def assignee_changed(event)
    return unless ENV['AUTO_TRANSLATE_ENABLED'] == 'true'

    conversation = extract_conversation_and_account(event)[0]
    return if conversation.assignee_id.blank?

    AutoTranslateBackfillJob.perform_later(conversation.id)
  end

  private

  def eligible?(message)
    return false unless message.incoming?
    return false if message.private?
    return false if message.content.blank?

    conversation = message.conversation
    # only once a human operator owns the conversation
    conversation.status == 'open' && conversation.assignee_id.present?
  end
end
