care_sla = Care::Sla::ConversationPresenter.for(conversation)

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
