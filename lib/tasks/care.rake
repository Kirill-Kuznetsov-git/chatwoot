# Обслуживание интеграции с Support Care (сегменты пользователей, SCC-100).
namespace :care do
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
end
