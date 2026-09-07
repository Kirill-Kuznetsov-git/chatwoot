# Подтягивает сегмент одного контакта из Support Care и пишет его в custom_attributes.
# Ставится CareSegmentListener'ом (идентификация контакта, создание диалога) и rake care:*.
class Care::SegmentSyncJob < ApplicationJob
  queue_as :low

  # Порядок важен: ActiveJob проверяет обработчики с конца. Неверный ключ или битый ответ —
  # выбросить и записать в лог; недоступный Care — повторить с растущей паузой.
  discard_on Care::Client::Error do |job, error|
    Rails.logger.error("Care::SegmentSyncJob discarded for contact #{job.arguments.first}: #{error.class}: #{error.message}")
  end
  retry_on Care::Client::Unavailable, wait: :polynomially_longer, attempts: 4

  def perform(contact_id, force: false)
    return unless Care::SegmentSync.enabled?

    contact = Contact.find_by(id: contact_id)
    return if contact.nil?
    return unless Care::SegmentSync.account_allowed?(contact.account_id)
    return unless Care::SegmentSync.identifier_valid?(contact.identifier)
    return if !force && Care::SegmentSync.fresh?(contact)

    segment = Care::Client.new.segment(contact.identifier)
    Care::SegmentSync.apply!(contact, Care::SegmentSync.attributes_for(segment))
  end
end
