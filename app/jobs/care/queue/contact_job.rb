# Сегмент контакта изменился (пришёл из Care или пересчитан ночью) — пере-применить очередь к его
# открытым и pending-диалогам. Закрывает гонку «диалог создан раньше, чем подтянулся сегмент».
class Care::Queue::ContactJob < ApplicationJob
  queue_as :default

  LIMIT = 20

  def perform(contact_id)
    return unless Care::SegmentSync.enabled?

    contact = Contact.find_by(id: contact_id)
    return if contact.nil?

    config = Care::Queue::Config.current
    contact.conversations.where(status: %i[open pending]).order(created_at: :desc).limit(LIMIT).each do |conversation|
      Care::Queue::Applier.apply!(conversation, config: config)
    end
  end
end
