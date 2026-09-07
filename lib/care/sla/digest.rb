# Ежедневный дайджест по SLA (SCC-102): по каждому классу за сутки — передач людям, первый ответ человека
# (p50/p90 и доля в KPI ≤ 6 ч), закрытые без ответа человека, нарушения по таймерам; плюс срез очереди сейчас.
# Считает по трекерам, а не по reporting_events — те же якоря, что и у лейблов/алертов.
class Care::Sla::Digest
  def initialize(date:, config:, account_id: nil)
    @date = date
    @config = config
    @account_id = account_id
  end

  def text
    lines = ["📊 SLA-дайджест за #{@date.strftime('%d.%m.%Y')} (UTC), конфиг v#{@config.version}"]
    @config.classes.each { |klass| lines << class_line(klass) }
    lines << open_line
    lines.join("\n")
  end

  private

  def day_scope
    from = @date.in_time_zone('UTC').beginning_of_day
    scope = Care::SlaTracker.where(started_at: from...(from + 1.day))
    scope = scope.where(account_id: @account_id) if @account_id
    scope
  end

  def class_line(klass)
    scope = day_scope.where(class_key: klass.key)
    total = scope.count
    return "#{klass.name}: передач людям 0" if total.zero?

    "#{klass.name}: передач людям #{total}, #{first_response_part(scope)}, " \
      "закрыто без ответа человека #{scope.where(first_response_at: nil, closed_reason: 'resolved').count}; " \
      "нарушений: #{breaches_part(scope)}"
  end

  def first_response_part(scope)
    minutes = scope.where.not(first_response_at: nil)
                   .pluck(Arel.sql('EXTRACT(EPOCH FROM (first_response_at - started_at)) / 60.0')).map(&:to_f).sort
    kpi = @config.kpi_first_response_minutes
    kpi_share = minutes.empty? ? 0 : (100.0 * minutes.count { |m| m <= kpi } / minutes.size).round
    "ответил человек #{minutes.size} (p50 #{percentile(minutes, 0.5)} мин, p90 #{percentile(minutes, 0.9)} мин, " \
      "в KPI #{kpi} мин — #{kpi_share} %)"
  end

  def breaches_part(scope)
    "первый ответ #{scope.where.not(fr_breached_at: nil).count}, ожидание #{scope.where.not(nr_breached_at: nil).count}, " \
      "решение #{scope.where.not(res_breached_at: nil).count}"
  end

  def open_line
    scope = Care::SlaTracker.active
    scope = scope.where(account_id: @account_id) if @account_id
    breached = scope.where("fr_state = 'breached' OR nr_state = 'breached' OR res_state = 'breached'").count
    at_risk = scope.where("fr_state = 'at_risk' OR nr_state = 'at_risk' OR res_state = 'at_risk'").count
    "Сейчас в очереди людей: #{scope.count} диалогов, с просрочкой #{breached}, под риском #{at_risk}"
  end

  # Ближайший по рангу элемент отсортированного массива (nearest-rank), без интерполяции.
  def percentile(sorted, share)
    return '—' if sorted.empty?

    index = [(share * sorted.size).ceil - 1, 0].max
    sorted[index].round
  end
end
