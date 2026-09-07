# Обслуживание интеграции с Support Care (сегменты пользователей, SCC-100).
namespace :care do
  desc 'Создать определения атрибутов сегмента на контакте (идемпотентно): rails care:segment_attribute_definitions[ACCOUNT_ID]'
  task :segment_attribute_definitions, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    created = Care::SegmentAttributeDefinitions.ensure!(account)
    puts "account #{account.id}: created #{created.size} definitions#{created.any? ? " (#{created.join(', ')})" : ''}"
  end

  desc 'Разово подтянуть сегмент одного контакта из Care (синхронно): rails care:segment_sync[CONTACT_ID]'
  task :segment_sync, [:contact_id] => :environment do |_t, args|
    contact = Contact.find(args[:contact_id])
    changed = Care::SegmentSyncJob.perform_now(contact.id, force: true)
    puts "contact #{contact.id}: #{changed ? 'segment updated' : 'segment unchanged (timestamp refreshed)'}"
  end
end
