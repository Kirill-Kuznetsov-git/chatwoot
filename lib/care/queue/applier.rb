# Ставит диалог в очередь ценных клиентов: определяет класс по сегменту контакта, создаёт или
# реактивирует SLA-трекер и сразу приводит диалог к нужному состоянию через Reconciler.
# Вызывается из джобов на события диалога (created / opened / resolved), после синка сегмента контакта
# и из Sweep (страховка на случай пропущенных событий и расширения конфига).
class Care::Queue::Applier
  def self.apply!(conversation, config: Care::Queue::Config.current, now: Time.current, started_at: nil)
    new(conversation, config: config, now: now).apply!(started_at: started_at)
  end

  def initialize(conversation, config:, now: Time.current)
    @conversation = conversation
    @config = config
    @now = now
  end

  # => трекер, если диалог в очереди людей; nil — вне очереди, ещё у бота или уже закрыт без трекера.
  def apply!(started_at: nil)
    return nil unless allowed?

    klass = @config.classify(@conversation.contact)
    tracker = Care::SlaTracker.find_by(conversation_id: @conversation.id)
    return drop!(tracker) if klass.nil?
    # Диалог ещё у бота: часы не идут, но приоритет и лейбл класса ставим сразу — так он виден в списке pending.
    return preapply!(klass) if @conversation.pending?
    return nil if tracker.nil? && !@conversation.open?

    reconcile!(tracker || build_tracker(klass, started_at))
  end

  private

  def allowed?
    Care::SegmentSync.enabled? && Care::SegmentSync.account_allowed?(@conversation.account_id)
  end

  # Сегмент/конфиг больше не относят контакт к очереди — снять наше и закрыть трекер, если он был активен.
  def drop!(tracker)
    Care::Sla::Reconciler.new(tracker, config: @config, now: @now).call if tracker&.active?
    nil
  end

  def preapply!(klass)
    return nil unless @config.queue_enabled

    @conversation.update!(priority: klass.chatwoot_priority) if @conversation.priority.blank? && klass.chatwoot_priority.present?
    missing = klass.labels - @conversation.label_list
    if missing.any?
      Care::Queue::Labels.ensure!(@conversation.account, missing)
      @conversation.add_labels(missing)
    end
    nil
  end

  def reconcile!(tracker)
    reactivate!(tracker) if !tracker.active? && @conversation.open?
    tracker.save! if tracker.new_record? || tracker.changed?
    Care::Sla::Reconciler.new(tracker, config: @config, now: @now).call
  end

  def build_tracker(klass, started_at)
    Care::SlaTracker.new(
      account_id: @conversation.account_id, conversation_id: @conversation.id, contact_id: @conversation.contact_id,
      class_key: klass.key, class_name: klass.name, config_version: @config.version, started_at: started_at || @now,
      # то, что уже стоит на диалоге и совпадает с классом, считаем своим (поставлено на этапе pending)
      priority_applied: (@conversation.priority if @conversation.priority.present? && @conversation.priority == klass.chatwoot_priority),
      labels_applied: klass.labels & @conversation.label_list
    )
  end

  # Повторное открытие после resolved — новый отсчёт решения; после untracked — просто продолжаем.
  def reactivate!(tracker)
    reopened = tracker.closed_reason == 'resolved'
    tracker.assign_attributes(active: true, closed_reason: nil, closed_at: nil, resolved_at: nil,
                              reopened_at: reopened ? @now : tracker.reopened_at)
  end
end
