module ManualEscalationActions
  extend ActiveSupport::Concern

  def manual_escalation_link
    return unless authorize_manual_escalation
    return render json: { error: 'Invalid Slack permalink' }, status: :unprocessable_entity unless valid_manual_escalation_url?

    @conversation.with_lock do
      attributes = (@conversation.custom_attributes || {}).merge(@conversation.manual_escalation_link_key => params[:url])
      @conversation.update!(custom_attributes: attributes)
    end
    render json: { @conversation.manual_escalation_link_key => params[:url] }
  end

  def manual_escalation_note
    return unless authorize_manual_escalation
    return render json: { error: 'Invalid escalation reference' }, status: :unprocessable_entity unless valid_manual_escalation_reference?

    note = @conversation.with_lock do
      @conversation.messages.find_by(source_id: "scc138:#{params[:event_id]}") ||
        @conversation.messages.create!(
          account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, sender: Current.user,
          message_type: :outgoing, private: true, content: "New reply in Slack thread: #{params[:url]}",
          source_id: "scc138:#{params[:event_id]}"
        )
    end
    render json: { id: note.id, private: note.private? }
  end

  private

  def authorize_manual_escalation
    allowed = @conversation.manual_escalation_enabled? &&
              (Current.user.is_a?(AgentBot) || Current.account_user&.administrator?)
    return true if allowed

    head :forbidden
    false
  end

  def valid_manual_escalation_reference?
    valid_manual_escalation_url? && params[:event_id].is_a?(String) && params[:event_id].match?(/\A[\w.:-]{1,200}\z/)
  end

  def valid_manual_escalation_url?
    channel = ENV.fetch('MANUAL_ESCALATION_SLACK_CHANNEL_ID', '').strip
    return false unless channel.match?(/\AC[A-Z0-9]+\z/) && params[:url].is_a?(String)

    params[:url].match?(%r{\Ahttps://starpets\.slack\.com/archives/#{Regexp.escape(channel)}/p\d{16}\z})
  end
end
