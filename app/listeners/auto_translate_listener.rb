# Enqueues auto-translation of messages, both directions, only for human-handled
# conversations (bot/pending conversations are skipped because the AI agent
# already replies in the user's language). Gated OFF by default
# (AUTO_TRANSLATE_ENABLED). Triggers:
#   - message_created (incoming): customer -> operator's UI language.
#   - message_created (outgoing): operator -> customer's front-end language.
#   - assignee_changed: on hand-off to a human, back-fill earlier incoming msgs.
class AutoTranslateListener < BaseListener
  def message_created(event)
    return unless ENV['AUTO_TRANSLATE_ENABLED'] == 'true'

    message = extract_message_and_account(event)[0]

    if incoming_eligible?(message)
      AutoTranslateJob.perform_later(message.id)
    elsif outgoing_eligible?(message)
      OutgoingAutoTranslateJob.perform_later(message.id)
    end
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

  def incoming_eligible?(message)
    return false unless message.incoming?

    human_owned_text?(message)
  end

  def outgoing_eligible?(message)
    return false unless message.outgoing?
    return false unless message.content_type == 'text'

    human_owned_text?(message)
  end

  def human_owned_text?(message)
    return false if message.private?
    return false if message.content.blank?

    conversation = message.conversation
    # only once a human operator owns the conversation
    conversation.status == 'open' && conversation.assignee_id.present?
  end
end
