# Ежеминутный тик SLA (config/schedule.yml): пересчитать все активные трекеры по текущему конфигу Care
# и подобрать открытые диалоги без трекера (Sweep). Один тик за раз — блокировка в Redis.
class Care::Sla::TickJob < ApplicationJob
  queue_as :default

  LOCK_KEY = 'care:sla:tick:lock'.freeze
  LOCK_TTL_SECONDS = 55

  def perform
    return unless Care::SegmentSync.enabled?
    return unless Redis::Alfred.set(LOCK_KEY, Time.current.to_i, nx: true, ex: LOCK_TTL_SECONDS)

    config = Care::Queue::Config.current
    stats = { reconciled: 0, errors: 0, swept: 0 }
    Care::SlaTracker.active.find_each(batch_size: 200) do |tracker|
      Care::Sla::Reconciler.new(tracker, config: config).call
      stats[:reconciled] += 1
    rescue StandardError => e
      stats[:errors] += 1
      Rails.logger.error("Care::Sla::TickJob tracker #{tracker.id}: #{e.class}: #{e.message}")
    end
    stats[:swept] = Care::Queue::Sweep.new(config: config).call
    Rails.logger.info("Care::Sla::TickJob config v#{config.version} (#{config.source}): #{stats}")
    stats
  ensure
    Redis::Alfred.delete(LOCK_KEY) if config
  end
end
