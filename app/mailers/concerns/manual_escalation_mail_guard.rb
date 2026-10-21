module ManualEscalationMailGuard
  extend ActiveSupport::Concern

  included do
    around_deliver :guard_manual_escalation_mail_delivery
  end

  private

  def filter_manual_escalation_mail(new_messages)
    @manual_escalation_new_messages = new_messages.to_a
    return false unless @conversation.manual_escalation_enabled? && @conversation.manually_escalated?

    @messages = @messages.reject { |message| public_bot_message?(message) }
    @manual_escalation_new_messages.reject! { |message| public_bot_message?(message) }
    true
  end

  def public_bot_message?(message)
    !message.private? && message.sender_type == 'AgentBot'
  end

  def suppress_manual_escalation_bot_email?(message)
    @conversation.manual_escalation_enabled? && @conversation.manually_escalated? && public_bot_message?(message)
  end

  def guard_manual_escalation_mail_delivery
    return yield unless @conversation&.manual_escalation_enabled?
    return yield unless @manual_escalation_new_messages&.any? { |message| public_bot_message?(message) }

    @conversation.reload.with_manual_escalation_lock do
      if @conversation.manually_escalated?
        resend_human_escalation_mail
      else
        yield
      end
    end
  end

  def resend_human_escalation_mail
    human_message = @manual_escalation_new_messages.select { |message| message.sender_type == 'User' }.min_by(&:id)
    return unless human_message

    ConversationReplyMailer.with(account: @conversation.account).reply_without_summary(@conversation, human_message.id).deliver_later
  end
end
