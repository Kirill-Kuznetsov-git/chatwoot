# Enqueues auto-translation of incoming customer messages into the operator's
# language. Gated OFF by default (AUTO_TRANSLATE_ENABLED) and only for
# human-handled conversations (status=open + a human assignee) — bot/pending
# conversations are skipped because the AI agent already replies in the user's
# language.
class AutoTranslateListener < BaseListener
  def message_created(event)
    return unless ENV['AUTO_TRANSLATE_ENABLED'] == 'true'

    message = extract_message_and_account(event)[0]
    return unless eligible?(message)

    AutoTranslateJob.perform_later(message.id)
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
