# Проактивная рассылка на сегмент контактов (SCC-45.13).
#
# Виджет-инбокс — единственный канал, где у контакта гарантированно есть адрес: исходящее
# сообщение в диалоге уходит контакту письмом (Messages::SendEmailNotificationService при
# continuity_via_email), а ответ по email возвращается в тот же диалог через ReplyMailbox.
# Поэтому рассылка = диалог + одно исходящее сообщение на каждого контакта аудитории, а
# «доставлено/ответы» считаются по campaign.conversations.
#
# Диалог создаётся сразу resolved: рассылка на тысячи контактов не должна залить очередь
# операторам. Ответ контакта переоткрывает диалог штатной логикой Message#reopen_conversation.
# Статус выставляется при создании, а не через resolved!, чтобы не разослать всем CSAT-опрос.
class Website::OneoffCampaignService
  pattr_initialize [:campaign!]

  def perform
    validate_campaign!

    audience_contacts.find_each(batch_size: 100) { |contact| deliver_to(contact) }

    campaign.completed!
  end

  private

  delegate :inbox, :account, to: :campaign

  def validate_campaign!
    raise "Invalid campaign #{campaign.id}" unless inbox.inbox_type == 'Website' && campaign.one_off?
    raise 'Completed Campaign' if campaign.completed?
  end

  # Контакты без email отсеиваем здесь: диалог для них создался бы, а письмо — нет,
  # и счётчик «отправлено» врал бы.
  def audience_contacts
    account.contacts.where(id: audience_contact_ids).where.not(email: [nil, ''])
  end

  def audience_contact_ids
    (segment_contact_ids + label_contact_ids).uniq
  end

  def segment_contact_ids
    segments.flat_map { |segment| contact_ids_for(segment) }
  end

  def segments
    segment_ids = campaign.audience.to_a.select { |item| item['type'] == 'Segment' }.pluck('id')
    return [] if segment_ids.blank?

    account.custom_filters.contact.where(id: segment_ids)
  end

  # Сегмент — сохранённый фильтр контактов, тот же payload, что применяет раздел «Контакты».
  # Пустой payload означал бы «все контакты» — такую аудиторию не рассылаем.
  def contact_ids_for(segment)
    payload = segment.query.to_h['payload']
    return [] if payload.blank?

    ::Contacts::FilterService.new(account, campaign.sender, { payload: payload }.with_indifferent_access).perform[:contacts].ids
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue => e
    Rails.logger.error "[Campaign #{campaign.id}] segment #{segment.id} is not resolvable: #{e.message}"
    []
  end

  def label_contact_ids
    label_ids = campaign.audience.to_a.select { |item| item['type'] == 'Label' }.pluck('id')
    titles = account.labels.where(id: label_ids).pluck(:title)
    return [] if titles.blank?

    account.contacts.tagged_with(titles, any: true).ids
  end

  # Повторный прогон (ретрай джобы) не должен слать второе письмо тому же контакту.
  def deliver_to(contact)
    return if campaign.conversations.exists?(contact_id: contact.id)

    conversation = ::Conversation.create!(conversation_params(contact_inbox_for(contact)))
    ::Messages::MessageBuilder.new(campaign.sender, conversation, message_params).perform
  rescue StandardError => e
    Rails.logger.error "[Campaign #{campaign.id}] failed for contact #{contact.id}: #{e.message}"
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  # Переиспользуем последнюю сессию виджета контакта: тогда переоткрытый ответом диалог
  # виден ему и в виджете, а не только в почте. Нет сессии — создаём новую.
  def contact_inbox_for(contact)
    contact.contact_inboxes.where(inbox_id: inbox.id).order(created_at: :desc).first ||
      ::ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: nil).perform
  end

  def conversation_params(contact_inbox)
    {
      account_id: account.id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      campaign_id: campaign.id,
      status: :resolved
    }
  end

  def message_params
    ActionController::Parameters.new({ content: campaign.message, campaign_id: campaign.id })
  end
end
