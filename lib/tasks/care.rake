# Обслуживание интеграции с Support Care (сегменты пользователей SCC-100, очереди и SLA SCC-102).
namespace :care do # rubocop:disable Metrics/BlockLength
  desc 'Создать определения атрибутов сегмента на контакте (идемпотентно): rails care:segment_attribute_definitions[ACCOUNT_ID]'
  task :segment_attribute_definitions, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    result = Care::SegmentAttributeDefinitions.ensure!(account)
    puts "account #{account.id}: created #{result[:created].size} (#{result[:created].join(', ')}), " \
         "descriptions updated #{result[:updated].size} (#{result[:updated].join(', ')})"
  end

  desc 'Разово подтянуть сегмент одного контакта из Care (синхронно): rails care:segment_sync[CONTACT_ID]'
  task :segment_sync, [:contact_id] => :environment do |_t, args|
    contact = Contact.find(args[:contact_id])
    changed = Care::SegmentSyncJob.perform_now(contact.id, force: true)
    puts "contact #{contact.id}: #{changed ? 'segment updated' : 'segment unchanged (timestamp refreshed)'}"
  end

  desc 'Бэкфилл сегмента ценным контактам (киты + Big за 90д): ' \
       'rails "care:segment_backfill_valuable[ACCOUNT_ID,RATE_PER_MIN,AFTER_ID]" (DRY_RUN=1 — только посчитать)'
  task :segment_backfill_valuable, [:account_id, :rate_per_minute, :after_id] => :environment do |_t, args|
    raise 'Care::SegmentSync выключен (CARE_SEGMENT_SYNC_ENABLED/CARE_API_URL/CARE_SERVICE_KEY)' unless Care::SegmentSync.enabled?

    account = Account.find(args[:account_id])
    $stdout.sync = true # на detached-дино stdout буферизуется — без этого прогресс виден только в конце
    logger = ActiveSupport::Logger.new($stdout)
    result = Care::SegmentBackfill.new(
      account: account,
      rate_per_minute: (args[:rate_per_minute] || 300).to_i,
      dry_run: ENV['DRY_RUN'] == '1',
      logger: logger
    ).run(after_id: args[:after_id].presence)
    puts "done: #{result.to_h}"
  end

  desc 'Показать действующий конфиг очередей/SLA (источник, версия, классы): rails care:queue_config'
  task queue_config: :environment do
    Care::Queue::Config.invalidate!
    config = Care::Queue::Config.current
    puts "source=#{config.source} version=#{config.version} queue=#{config.queue_enabled} sla_labels=#{config.sla_labels_enabled} " \
         "alerts=#{config.alerts_enabled} digest=#{config.digest_enabled}@#{config.digest_hour_utc}h risk_share=#{config.risk_share}"
    config.classes.each do |klass|
      puts "  #{klass.key} (#{klass.name}): weights=#{klass.weights} tiers=#{klass.tiers} priority=#{klass.chatwoot_priority} " \
           "labels=#{klass.labels} sla=#{klass.sla_enabled} fr=#{klass.first_response_minutes} nr=#{klass.next_response_minutes} " \
           "res=#{klass.resolution_minutes} alert=#{klass.alert_on_breach} escalate=#{klass.escalate_priority_on_breach}"
    end
  end

  desc 'Бэкфилл очереди: трекеры и приоритеты открытым диалогам ценных клиентов: rails care:queue_backfill_open'
  task queue_backfill_open: :environment do
    raise 'Care::SegmentSync выключен' unless Care::SegmentSync.enabled?

    $stdout.sync = true
    config = Care::Queue::Config.current
    total = 0
    20.times do
      count = Care::Queue::Sweep.new(config: config, limit: 500).call
      total += count
      puts "swept #{count} (total #{total})"
      break if count.zero?
    end
    puts "done: #{total} трекеров, активных сейчас #{Care::SlaTracker.active.count}"
  end

  desc 'Один тик SLA вручную: rails care:sla_tick'
  task sla_tick: :environment do
    puts Care::Sla::TickJob.perform_now.inspect
  end

  desc 'Дайджест SLA за дату (UTC, по умолчанию вчера), без проверки часа и дедупа: rails "care:sla_digest[2026-09-08]"'
  task :sla_digest, [:date] => :environment do |_t, args|
    puts Care::Sla::DigestJob.perform_now(args[:date], force: true)
  end

  desc 'Сортировка списка диалогов как живая очередь (приоритет, затем ожидание) агентам, у кого своя не выбрана: ' \
       'rails care:default_sort_priority[ACCOUNT_ID]'
  task :default_sort_priority, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    queue_order = 'priority_desc_waiting_since_asc'
    # Не выбрана вовсе или стоит простой приоритет, который мы же и выставляли раньше — обновляем;
    # осознанный выбор агента (по активности, по дате) не трогаем.
    replaceable = [nil, '', 'priority_desc']
    changed = account.users.find_each.count do |user|
      settings = user.ui_settings.to_h.deep_dup
      filter = settings['conversations_filter_by'].to_h
      next false unless replaceable.include?(filter['order_by'])

      user.update!(ui_settings: settings.merge('conversations_filter_by' => filter.merge('order_by' => queue_order)))
      true
    end
    puts "account #{account.id}: очередная сортировка выставлена #{changed} агентам"
  end
end
