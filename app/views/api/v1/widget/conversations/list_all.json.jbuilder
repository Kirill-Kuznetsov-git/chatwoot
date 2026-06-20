json.array! @conversations do |conversation|
  json.id conversation.display_id
  json.inbox_id conversation.inbox_id
  json.status conversation.status
  json.contact_last_seen_at conversation.contact_last_seen_at.to_i
  json.last_activity_at conversation.last_activity_at.to_i
  json.labels conversation.label_list

  last_message = conversation.messages.where.not(message_type: :activity).reorder(created_at: :desc).first
  if last_message
    json.last_message do
      json.id last_message.id
      json.content last_message.content
      json.message_type last_message.message_type_before_type_cast
      json.content_attributes last_message.content_attributes
      json.created_at last_message.created_at.to_i
    end
  else
    json.last_message nil
  end
end
