module ManualEscalationBroadcast
  extend ActiveSupport::Concern

  private

  def broadcast_conversation(account, tokens, event_name, data, conversation)
    internal_keys = conversation.manual_escalation_internal_keys
    return broadcast(account, tokens, event_name, data) if (conversation.custom_attributes || {}).slice(*internal_keys).empty?

    customer_tokens = contact_inbox_tokens(conversation.contact_inbox) & tokens
    broadcast(account, tokens - customer_tokens, event_name, data)
    customer_data = data.dup
    customer_data[:conversation] = data[:conversation].dup if data[:conversation]
    attributes = customer_data[:conversation] || customer_data
    attributes[:custom_attributes] = conversation.public_custom_attributes
    broadcast(account, customer_tokens, event_name, customer_data)
  end
end
