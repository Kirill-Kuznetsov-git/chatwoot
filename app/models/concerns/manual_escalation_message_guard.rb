module ManualEscalationMessageGuard
  extend ActiveSupport::Concern

  included do
    validate :protect_manual_escalation_reply, on: :create
  end

  private

  def protect_manual_escalation_reply
    return unless public_bot_reply?
    return unless conversation&.manual_escalation_enabled?

    # The lock belongs to Message's save transaction, so a concurrent label
    # cannot commit between this check and persistence of a public bot reply.
    locked_conversation = Conversation.find(conversation_id)
    locked_conversation.with_manual_escalation_lock do
      errors.add(:base, 'Conversation is held for manual escalation') if locked_conversation.manually_escalated?
    end
  end

  def public_bot_reply?
    !private? && (outgoing? || template?) && (sender.is_a?(AgentBot) || Current.user.is_a?(AgentBot))
  end
end
