# Отдаёт сроки нашего SLA-движка (SCC-102) в том виде, который понимает штатный фронт Chatwoot:
# карточка диалога рисует таймер компонентом SLACardLabel.vue через helper/slaHelper.js, а тот ждёт
# объект applied_sla с полями sla_frt_due_at / sla_nrt_due_at / sla_rt_due_at (unix) и id.
# Enterprise-модуль SLA при этом не используется и не включается — считаем мы сами.
#
# Показ включается флагом `sla_timer_enabled` в конфиге Care, чтобы таймеры не появились у операторов
# раньше, чем этого захотят в поддержке.
class Care::Sla::ConversationPresenter
  # Конфиг читается из минутного кэша в Redis, отдельного запроса в Care на каждый диалог нет.
  def self.enabled?
    Care::SegmentSync.enabled? && Care::Queue::Config.current.sla_timer_enabled
  end

  # => Hash для jbuilder или nil, если таймер выключен либо диалог не в очереди ценных.
  def self.for(conversation)
    return nil unless enabled?

    tracker = Care::SlaTracker.find_by(conversation_id: conversation.id, active: true)
    return nil if tracker.nil?

    {
      id: tracker.id,
      sla_name: tracker.class_name,
      sla_frt_due_at: tracker.fr_due_at&.to_i,
      sla_nrt_due_at: tracker.nr_due_at&.to_i,
      sla_rt_due_at: tracker.res_due_at&.to_i
    }
  end
end
