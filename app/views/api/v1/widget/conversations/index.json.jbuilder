if @conversation
  json.id @conversation.display_id
  json.inbox_id @conversation.inbox_id
  json.contact_last_seen_at @conversation.contact_last_seen_at.to_i
  json.status @conversation.status
  json.campaign_id @conversation.campaign_id
  json.guest_email_only @conversation.additional_attributes.to_h['guest_email_only'] == true
end
