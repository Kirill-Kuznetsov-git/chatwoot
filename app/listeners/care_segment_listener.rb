# Синхронизация сегмента пользователя из Support Care (SCC-100). Выключено по умолчанию
# (Care::SegmentSync.enabled?). Триггеры:
#   - contact.created / contact.updated с identifier — виджет идентифицировал юзера (setUser);
#     обычно это ДО первого сообщения, так что к conversation.created сегмент уже на контакте
#     и автоматизации при создании диалога его видят.
#   - conversation.created — страховка: если сегмента нет или он старше суток.
class CareSegmentListener < BaseListener
  def contact_created(event)
    return unless Care::SegmentSync.enabled?

    enqueue_if_identified(event.data[:contact])
  end

  def contact_updated(event)
    return unless Care::SegmentSync.enabled?

    changed = (event.data[:changed_attributes] || {}).to_h
    return unless changed.key?('identifier') || changed.key?(:identifier)

    enqueue_if_identified(event.data[:contact])
  end

  def conversation_created(event)
    return unless Care::SegmentSync.enabled?

    conversation = extract_conversation_and_account(event)[0]
    contact = conversation&.contact
    return if contact.nil? || Care::SegmentSync.fresh?(contact)

    enqueue_if_identified(contact)
  end

  private

  def enqueue_if_identified(contact)
    return if contact.nil?
    return unless Care::SegmentSync.account_allowed?(contact.account_id)
    return unless Care::SegmentSync.identifier_valid?(contact.identifier)

    Care::SegmentSyncJob.perform_later(contact.id)
  end
end
