# Реакция на событие диалога (created / opened / resolved): поставить в очередь ценных, стартовать или
# закрыть SLA-трекер. Ставится CareQueueListener'ом. Конфиг берётся из кэша, Care недоступен — fallback.
class Care::Queue::ConversationJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, _event_name = nil)
    return unless Care::SegmentSync.enabled?

    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil?

    Care::Queue::Applier.apply!(conversation)
  end
end
