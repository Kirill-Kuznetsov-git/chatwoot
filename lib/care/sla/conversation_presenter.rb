# Что Support Care добавляет в API диалога (SCC-102). Оба блока живут вне тегов и вне полей поддержки:
#
# * care_segment — значимость клиента. В meta.sender список диалогов отдаёт контакт без
#   custom_attributes, поэтому сегмент кладём отдельным полем: карточка рисует его значком с эмодзи.
# * applied_sla — сроки нашего SLA-движка в формате, который понимает штатный таймер Chatwoot
#   (components-next/.../SLACardLabel.vue + helper/slaHelper.js). Enterprise-модуль SLA не включаем
#   и не используем, считаем сами. Показ гейтится флагом sla_timer_enabled в конфиге Care.
class Care::Sla::ConversationPresenter
  SEGMENT_KEYS = %w[segment_label segment_weight segment_tier_90d].freeze

  def self.config
    Care::Queue::Config.current
  end

  # => Hash с label/weight/tier_90d или nil, если сегмента у контакта нет.
  def self.segment_for(conversation)
    return nil unless Care::SegmentSync.enabled?

    attributes = conversation.contact&.custom_attributes.to_h
    return nil if attributes['segment_label'].blank?

    {
      label: attributes['segment_label'],
      weight: attributes['segment_weight'],
      tier_90d: attributes['segment_tier_90d']
    }
  end

  # => Hash со сроками для таймера или nil, если таймер выключен либо диалог не в очереди ценных.
  def self.sla_for(conversation)
    return nil unless Care::SegmentSync.enabled? && config.sla_timer_enabled

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
