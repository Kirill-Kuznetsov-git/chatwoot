# Очередь ценных клиентов и SLA (SCC-102). Выключено вместе с Care::SegmentSync. События:
#   - conversation.created — приоритет/лейбл класса сразу (диалог ещё может быть у бота);
#   - conversation.opened  — передача человеку или повторное открытие: старт/реактивация SLA-трекера;
#   - conversation.resolved — закрыть трекер (если он есть).
# Контакты без сегмента пропускаем: после синка сегмента их догонит Care::Queue::ContactJob.
class CareQueueListener < BaseListener
  def conversation_created(event)
    # Рассылочный диалог (Website::OneoffCampaignService) создаётся сразу resolved и оператору
    # не адресован — классифицируем его только когда контакт ответит (conversation_opened),
    # иначе рассылка на сегмент залила бы очередь бесполезными задачами.
    conversation = extract_conversation_and_account(event)[0]
    return if conversation&.campaign_id.present? && conversation.resolved?

    enqueue(event, 'conversation_created')
  end

  def conversation_opened(event)
    enqueue(event, 'conversation_opened')
  end

  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.nil? || !Care::SegmentSync.enabled?
    return unless Care::SlaTracker.active.exists?(conversation_id: conversation.id)

    Care::Queue::ConversationJob.perform_later(conversation.id, 'conversation_resolved')
  end

  private

  def enqueue(event, event_name)
    return unless Care::SegmentSync.enabled?

    conversation = extract_conversation_and_account(event)[0]
    return if conversation.nil?
    return unless Care::SegmentSync.account_allowed?(conversation.account_id)
    return if conversation.contact&.custom_attributes.to_h['segment_weight'].blank?

    Care::Queue::ConversationJob.perform_later(conversation.id, event_name)
  end
end
