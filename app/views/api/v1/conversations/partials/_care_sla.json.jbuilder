care_segment = Care::Sla::ConversationPresenter.segment_for(conversation)

if care_segment.present?
  json.care_segment do
    json.label care_segment[:label]
    json.weight care_segment[:weight]
    json.tier_90d care_segment[:tier_90d]
  end
end

care_sla = Care::Sla::ConversationPresenter.sla_for(conversation)

if care_sla.present?
  json.applied_sla do
    json.id care_sla[:id]
    json.sla_name care_sla[:sla_name]
    json.sla_frt_due_at care_sla[:sla_frt_due_at]
    json.sla_nrt_due_at care_sla[:sla_nrt_due_at]
    json.sla_rt_due_at care_sla[:sla_rt_due_at]
  end
  json.sla_events []
end
