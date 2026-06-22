# Enqueues auto-translation of messages, both directions. Gated OFF by default
# (AUTO_TRANSLATE_ENABLED). Triggers:
#   - message_created (incoming): customer -> operator's UI language. Only once a
#     human operator owns the conversation (status open + assignee), since the AI
#     agent handles bot/pending conversations in the user's language already.
#   - message_created (outgoing): human operator reply -> customer's language,
#     regardless of assignment. human_response? excludes AgentBot/Captain/
#     automation/campaign so bot output is never re-translated.
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

  # Translate any human operator reply — regardless of assignment. human_response?
  # already excludes AgentBot ("StarPets AI" replies in the user's language),
  # Captain, automation rules and campaigns, so we don't re-translate bot output.
  def outgoing_eligible?(message)
    # human_response? is private on Message; call via send (no public equivalent).
    return false unless message.send(:human_response?)
    return false if message.private?
    return false unless message.content_type == 'text'
    return false if message.content.blank?

    true
  end

  def human_owned_text?(message)
    return false if message.private?
    return false if message.content.blank?

    conversation = message.conversation
    # only once a human operator owns the conversation
    conversation.status == 'open' && conversation.assignee_id.present?
  end
end
