# Чистая функция: (якоря трекера, поля диалога, класс, конфиг, now) → сроки и состояния трёх таймеров.
# Ничего не пишет, поэтому её можно вызывать сколько угодно раз и после любой смены конфига результат
# всегда согласован с текущими настройками.
#
# Таймеры:
#   fr  — первый ответ человека: от started_at (передача человеку) до conversation.first_reply_created_at
#         (Chatwoot ставит его только по ответу человека, боты не считаются);
#   nr  — ответ на сообщение клиента: от conversation.waiting_since (ставится входящим, снимается любым ответом);
#   res — решение: от started_at (или reopened_at после повторного открытия) до resolved.
# Состояния: none — цели нет; ok; at_risk — прошло ≥ risk_share окна; breached — срок прошёл, не выполнено
# (или выполнено с опозданием — факт нарушения остаётся); met — выполнено в срок.
class Care::Sla::Evaluator
  Result = Struct.new(:first_response_at, :fr_due_at, :fr_state, :nr_anchor_at, :nr_due_at, :nr_state,
                      :res_due_at, :res_state, keyword_init: true)

  def initialize(tracker, conversation, klass, config, now: Time.current)
    @tracker = tracker
    @conversation = conversation
    @klass = klass
    @config = config
    @now = now
  end

  def call
    first_response_at = compute_first_response_at
    # Диалог решён без ответа человека (бот/клиент закрыли сами): часы первого ответа останавливаются
    # в момент решения — успели до срока → ok, не успели → breached.
    fr_due, fr_state = clock(minutes: @klass.first_response_minutes, anchor: @tracker.started_at, done_at: first_response_at,
                             cutoff: resolved_at)

    nr_anchor = @conversation.resolved? ? nil : @conversation.waiting_since
    nr_due, nr_state = clock(minutes: @klass.next_response_minutes, anchor: nr_anchor, done_at: nil)

    res_due, res_state = clock(minutes: @klass.resolution_minutes, anchor: @tracker.reopened_at || @tracker.started_at,
                               done_at: resolved_at)

    Result.new(first_response_at: first_response_at, fr_due_at: fr_due, fr_state: fr_state,
               nr_anchor_at: nr_anchor, nr_due_at: nr_due, nr_state: nr_state,
               res_due_at: res_due, res_state: res_state)
  end

  private

  # Человек ответил ещё до передачи (вмешался в бот-фазу) — считаем выполненным в момент передачи.
  def compute_first_response_at
    reply_at = @conversation.first_reply_created_at
    return nil if reply_at.blank?

    [reply_at, @tracker.started_at].max
  end

  def resolved_at
    return nil unless @conversation.resolved?

    @tracker.resolved_at || @now
  end

  def clock(minutes:, anchor:, done_at:, cutoff: nil)
    return [nil, 'none'] if minutes.blank? || minutes <= 0 || !@klass.sla_enabled
    return [nil, 'ok'] if anchor.blank?

    due = anchor + minutes.minutes
    risk_at = anchor + (minutes * @config.risk_share).minutes
    [due, state_for(due, risk_at, done_at, cutoff)]
  end

  def state_for(due, risk_at, done_at, cutoff)
    return done_at <= due ? 'met' : 'breached' if done_at.present?
    return cutoff <= due ? 'ok' : 'breached' if cutoff.present?
    return 'breached' if @now >= due
    return 'at_risk' if @now >= risk_at

    'ok'
  end
end
