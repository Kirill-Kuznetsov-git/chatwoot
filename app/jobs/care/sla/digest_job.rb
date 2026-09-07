# Ежедневный SLA-дайджест в Slack. Крон дёргает каждый час; час отправки — из конфига Care
# (digest_hour_utc), чтобы его можно было менять без релиза. Повторная отправка за день исключена ключом в Redis.
class Care::Sla::DigestJob < ApplicationJob
  queue_as :low

  DEDUPE_TTL_SECONDS = 3.days.to_i

  # date: 'YYYY-MM-DD' (по умолчанию вчера по UTC); force — из rake, без проверки часа и дедупа.
  def perform(date = nil, force: false)
    return unless Care::SegmentSync.enabled?

    config = Care::Queue::Config.current
    now = Time.current.utc
    return unless force || due_now?(config, now)

    day = date.present? ? Date.parse(date.to_s) : now.to_date - 1
    return unless force || claim!(day)

    text = Care::Sla::Digest.new(date: day, config: config).text
    Care::Sla::Notifier.digest(text)
    text
  end

  private

  def due_now?(config, now)
    config.digest_enabled && now.hour == config.digest_hour_utc
  end

  def claim!(day)
    Redis::Alfred.set("care:sla:digest:#{day.iso8601}", '1', nx: true, ex: DEDUPE_TTL_SECONDS)
  end
end
