# Приводит диалог и его трекер к состоянию, вытекающему из (якоря, текущий сегмент контакта, текущий конфиг):
# класс, приоритет, лейблы, приватные заметки и алерты о просрочках. Идемпотентен — вызывается каждую минуту
# из Care::Sla::TickJob и сразу из Applier. Ручные правки операторов не перетирает: приоритет меняем,
# только пока он равен выставленному нами; снимаем только те лейблы, которые ставили сами.
class Care::Sla::Reconciler
  RISK_LABEL = Care::Queue::Config::RISK_LABEL
  BREACH_LABEL = Care::Queue::Config::BREACH_LABEL

  def initialize(tracker, config:, now: Time.current, notifier: Care::Sla::Notifier)
    @tracker = tracker
    @config = config
    @now = now
    @notifier = notifier
  end

  def call
    conversation = @tracker.conversation
    contact = conversation.contact
    klass = @config.classify(contact)
    return untrack!(conversation) if klass.nil?

    result = Care::Sla::Evaluator.new(@tracker, conversation, klass, @config, now: @now).call
    newly_breached = breach_transitions(result)

    assign_result(klass, contact, result)
    newly_breached.each { |clock| record_breach(clock, result) }
    finalize_resolved(conversation)
    apply_priority(conversation, klass)
    apply_labels(conversation, klass)
    @tracker.save!
    notify(conversation, klass, result, newly_breached)
    @tracker
  end

  private

  def assign_result(klass, contact, result)
    @tracker.assign_attributes(
      class_key: klass.key, class_name: klass.name, config_version: @config.version, contact_id: contact.id,
      first_response_at: result.first_response_at, fr_due_at: result.fr_due_at, fr_state: result.fr_state,
      nr_anchor_at: result.nr_anchor_at, nr_due_at: result.nr_due_at, nr_state: result.nr_state,
      res_due_at: result.res_due_at, res_state: result.res_state
    )
  end

  # Таймеры, которые просрочились именно сейчас (по ним ещё нет отметки). Для nr — по эпизоду ожидания.
  def breach_transitions(result)
    clocks = []
    clocks << :fr if result.fr_state == 'breached' && @tracker.fr_breached_at.nil?
    clocks << :res if result.res_state == 'breached' && @tracker.res_breached_at.nil?
    clocks << :nr if result.nr_state == 'breached' && new_waiting_episode?(result)
    clocks
  end

  def new_waiting_episode?(result)
    @tracker.nr_breached_anchor_at.nil? || @tracker.nr_breached_anchor_at.to_i != result.nr_anchor_at.to_i
  end

  def record_breach(clock, result)
    case clock
    when :fr then @tracker.fr_breached_at = result.fr_due_at
    when :res then @tracker.res_breached_at = result.res_due_at
    when :nr
      @tracker.nr_breached_at = result.nr_due_at
      @tracker.nr_breached_anchor_at = result.nr_anchor_at
    end
  end

  def finalize_resolved(conversation)
    return unless conversation.resolved?

    @tracker.resolved_at ||= @now
    @tracker.active = false
    @tracker.closed_reason = 'resolved'
    @tracker.closed_at ||= @now
  end

  def desired_priority(klass)
    return nil unless @config.queue_enabled
    return klass.escalate_priority_on_breach if @tracker.breached? && klass.escalate_priority_on_breach.present?

    klass.chatwoot_priority
  end

  def apply_priority(conversation, klass)
    return if @tracker.priority_manual

    current = conversation.priority
    if current != @tracker.priority_applied
      # приоритет поменяли руками (или сняли) — с этого момента диалог ведёт оператор
      @tracker.priority_manual = true
      return
    end

    desired = desired_priority(klass)
    return if desired == current

    conversation.update!(priority: desired)
    @tracker.priority_applied = desired
  end

  # Лейбл нарушения остаётся, если нарушение было хоть раз (история для лида); риск — только пока диалог открыт.
  def desired_labels(klass)
    labels = []
    labels.concat(klass.labels) if @config.queue_enabled
    if @config.sla_labels_enabled
      if ever_breached?
        labels << BREACH_LABEL
      elsif @tracker.active && @tracker.at_risk?
        labels << RISK_LABEL
      end
    end
    labels.uniq
  end

  def ever_breached?
    [@tracker.fr_breached_at, @tracker.nr_breached_at, @tracker.res_breached_at].any?(&:present?)
  end

  def apply_labels(conversation, klass)
    desired = desired_labels(klass)
    ours = Array(@tracker.labels_applied)
    current = conversation.label_list
    to_remove = (ours - desired) & current
    to_add = desired - current
    @tracker.labels_applied = (ours & desired) + to_add
    return if to_remove.empty? && to_add.empty?

    Care::Queue::Labels.ensure!(conversation.account, to_add)
    conversation.update_labels((current - to_remove + to_add).uniq)
  end

  def notify(conversation, klass, result, newly_breached)
    newly_breached.each do |clock|
      text = breach_text(clock, klass, result)
      add_private_note(conversation, text) if @config.sla_labels_enabled
      next unless @config.alerts_enabled && klass.alert_on_breach

      @notifier.breach(conversation: conversation, klass: klass, clock: clock, text: text)
    end
  end

  def breach_text(clock, klass, result)
    case clock
    when :fr
      "⏱ SLA #{klass.name}: первый ответ человека не дан за #{klass.first_response_minutes} мин " \
      "после передачи (#{msk(@tracker.started_at)})."
    when :nr
      "⏱ SLA #{klass.name}: клиент ждёт ответа дольше #{klass.next_response_minutes} мин (с #{msk(result.nr_anchor_at)})."
    when :res
      "⏱ SLA #{klass.name}: диалог не решён за #{format('%g', klass.resolution_minutes / 60.0)} ч после передачи " \
      "(#{msk(@tracker.reopened_at || @tracker.started_at)})."
    end
  end

  def msk(time)
    time.in_time_zone('Europe/Moscow').strftime('%d.%m %H:%M МСК')
  end

  def add_private_note(conversation, text)
    Messages::MessageBuilder.new(nil, conversation, { content: text, private: true }).perform
  rescue StandardError => e
    Rails.logger.error("Care::Sla::Reconciler note for conversation #{conversation.id}: #{e.class}: #{e.message}")
  end

  # Контакт больше не в очереди (сегмент или конфиг изменились): снять наше и закрыть трекер.
  def untrack!(conversation)
    ours = Array(@tracker.labels_applied) & conversation.label_list
    conversation.update_labels(conversation.label_list - ours) if ours.any?
    if !@tracker.priority_manual && @tracker.priority_applied.present? && conversation.priority == @tracker.priority_applied
      conversation.update!(priority: nil)
    end
    @tracker.update!(active: false, closed_reason: 'untracked', closed_at: @now, labels_applied: [], priority_applied: nil,
                     config_version: @config.version)
    @tracker
  end
end
