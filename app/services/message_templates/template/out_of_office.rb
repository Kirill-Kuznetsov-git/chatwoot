class MessageTemplates::Template::OutOfOffice
  pattr_initialize [:conversation!]

  # StarPets: out-of-office sent in the USER's language (contact locale / browser
  # language), not the inbox's static language. Falls back to the inbox
  # out_of_office_message when the language is unknown / not localized here.
  LOCALIZED_MESSAGES = {
    'en' => "Hey! 👋 Our operators are offline right now, but we got your message. A GPT StarPets consultant will assist you now, and an operator will step in if needed.\n\nPlease describe what happened. If this is about a payment, withdrawal, or order, you can also send the order ID or the last 7 characters of the transaction ID.\nWe’ll get back to you during working hours.",
    'ru' => "Сейчас операторов нет на линии, но мы получили твоё сообщение. Сейчас вам поможет GPT-консультант StarPets, а если понадобится, то подключится оператор.\n\nОпиши, пожалуйста, что случилось. Если вопрос про оплату, вывод или заказ — сразу пришли ID заказа или последние 7 символов ID транзакции.\nМы вернёмся с ответом в рабочее время.",
    'tr' => "Şu anda hatta operatör yok ama mesajını aldık. Sana StarPets GPT-konsültanı yardımcı olacak, gerekirse bir operatör de devreye girer.\n\nLütfen ne yaşandığını anlat. Konu ödeme, çekim veya sipariş ise — hemen sipariş ID'sini veya işlem ID'sinin son 7 karakterini gönder.\nÇalışma saatleri içinde sana dönüş yapacağız."
  }.freeze

  def self.perform_if_applicable(conversation)
    inbox = conversation.inbox
    return unless inbox.out_of_office?
    return if inbox.out_of_office_message.blank?

    new(conversation: conversation).perform
  end

  def perform
    ActiveRecord::Base.transaction do
      conversation.messages.create!(out_of_office_message_params)
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    true
  end

  private

  delegate :contact, :account, to: :conversation
  delegate :inbox, to: :message

  def out_of_office_message_params
    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :template,
      content: localized_out_of_office_message
    }
  end

  # User's language → localized text; fall back to the inbox's static message.
  def localized_out_of_office_message
    LOCALIZED_MESSAGES[conversation_language] || @conversation.inbox&.out_of_office_message
  end

  def conversation_language
    raw = @conversation.contact&.custom_attributes&.dig('language').presence ||
          @conversation.additional_attributes&.dig('browser_language').presence
    raw.to_s.split(/[-_]/).first.downcase.presence
  end
end
