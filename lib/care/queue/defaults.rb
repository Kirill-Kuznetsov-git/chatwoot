# Аварийный fallback конфига очередей/SLA: используется, только если Care недоступен, а в Redis нет
# last-good копии. Дублирует дефолты Care (backend/app/services/queue_config.py: DEFAULT_CLASSES и флаги)
# — менять синхронно. Источники чисел: SCC-77 (VIP 30 мин / 12 ч, default 2 ч / 24 ч), SCC-102 (KPI 6 ч).
module Care::Queue::Defaults
  SETTINGS = {
    'classes' => [
      { 'key' => 'vip', 'name' => 'VIP', 'weights' => ['Mega Whale', 'Big Whale', 'Whale'], 'tiers' => [],
        'chatwoot_priority' => 'urgent', 'labels' => ['vip'], 'sla_enabled' => true,
        'first_response_minutes' => 30, 'next_response_minutes' => 60, 'resolution_minutes' => 720,
        'alert_on_breach' => true, 'escalate_priority_on_breach' => nil },
      { 'key' => 'big', 'name' => 'Big', 'weights' => ['Big Fish'], 'tiers' => ['Big'],
        'chatwoot_priority' => 'high', 'labels' => [], 'sla_enabled' => true,
        'first_response_minutes' => 120, 'next_response_minutes' => 240, 'resolution_minutes' => 1440,
        'alert_on_breach' => false, 'escalate_priority_on_breach' => nil }
    ],
    'risk_share' => 0.8,
    'queue_enabled' => true,
    'sla_labels_enabled' => false,
    'sla_timer_enabled' => false,
    'alerts_enabled' => false,
    'digest_enabled' => true,
    'digest_hour_utc' => 6,
    'kpi_first_response_minutes' => 360
  }.freeze
end
