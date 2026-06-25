class MessageTemplates::Template::OutOfOffice
  pattr_initialize [:conversation!]

  # StarPets: out-of-office sent in the USER's language (contact locale / browser
  # language), not the inbox's static language. Falls back to the inbox
  # out_of_office_message when the language is unknown / not localized here.
  LOCALIZED_MESSAGES = {
    'en' => "Hey! 👋 Our operators are offline right now, but we got your message. A GPT StarPets consultant will assist you now, and an operator will step in if needed.\n\nPlease describe what happened. If this is about a payment, withdrawal, or order, you can also send the order ID or the last 7 characters of the transaction ID.\nWe’ll get back to you during working hours.",
    'ru' => "Сейчас операторов нет на линии, но мы получили твоё сообщение. Сейчас вам поможет GPT-консультант StarPets, а если понадобится, то подключится оператор.\n\nОпиши, пожалуйста, что случилось. Если вопрос про оплату, вывод или заказ — сразу пришли ID заказа или последние 7 символов ID транзакции.\nМы вернёмся с ответом в рабочее время.",
    'tr' => "Şu anda hatta operatör yok ama mesajını aldık. Sana StarPets GPT-konsültanı yardımcı olacak, gerekirse bir operatör de devreye girer.\n\nLütfen ne yaşandığını anlat. Konu ödeme, çekim veya sipariş ise — hemen sipariş ID'sini veya işlem ID'sinin son 7 karakterini gönder.\nÇalışma saatleri içinde sana dönüş yapacağız.",
    'fr' => "Salut ! 👋 Nos opérateurs sont hors ligne pour le moment, mais nous avons bien reçu ton message. Un consultant GPT StarPets va t'aider maintenant, et un opérateur prendra le relais si besoin.\n\nDécris-nous ce qui s'est passé. Si c'est au sujet d'un paiement, d'un retrait ou d'une commande, tu peux aussi envoyer l'ID de commande ou les 7 derniers caractères de l'ID de transaction.\nNous reviendrons vers toi pendant les heures de travail.",
    'de' => "Hey! 👋 Unsere Mitarbeiter sind gerade offline, aber wir haben deine Nachricht erhalten. Ein GPT-StarPets-Berater hilft dir jetzt, und ein Mitarbeiter übernimmt bei Bedarf.\n\nBeschreibe bitte, was passiert ist. Wenn es um eine Zahlung, Auszahlung oder Bestellung geht, kannst du auch die Bestell-ID oder die letzten 7 Zeichen der Transaktions-ID senden.\nWir melden uns während der Arbeitszeiten bei dir.",
    'pt' => "Olá! 👋 Os nossos operadores estão offline neste momento, mas recebemos a tua mensagem. Um consultor GPT da StarPets vai ajudar-te agora e, se for preciso, um operador entra em ação.\n\nDescreve o que aconteceu. Se for sobre pagamento, levantamento ou encomenda, podes enviar o ID da encomenda ou os últimos 7 caracteres do ID da transação.\nVamos responder-te durante o horário de trabalho.",
    'es' => "¡Hola! 👋 Nuestros operadores están desconectados ahora mismo, pero recibimos tu mensaje. Un consultor GPT de StarPets te ayudará ahora y, si hace falta, intervendrá un operador.\n\nCuéntanos qué pasó. Si es sobre un pago, retiro o pedido, también puedes enviar el ID del pedido o los últimos 7 caracteres del ID de la transacción.\nTe responderemos en horario laboral.",
    'it' => "Ciao! 👋 I nostri operatori sono offline in questo momento, ma abbiamo ricevuto il tuo messaggio. Un consulente GPT di StarPets ti aiuterà ora e, se necessario, interverrà un operatore.\n\nRaccontaci cosa è successo. Se riguarda un pagamento, un prelievo o un ordine, puoi anche inviare l'ID dell'ordine o gli ultimi 7 caratteri dell'ID della transazione.\nTi risponderemo durante l'orario di lavoro.",
    'vi' => "Chào bạn! 👋 Hiện tại nhân viên của chúng tôi đang ngoại tuyến, nhưng chúng tôi đã nhận được tin nhắn của bạn. Trợ lý GPT StarPets sẽ hỗ trợ bạn ngay bây giờ, và nhân viên sẽ tham gia nếu cần.\n\nHãy mô tả chuyện gì đã xảy ra. Nếu liên quan đến thanh toán, rút tiền hoặc đơn hàng, bạn cũng có thể gửi ID đơn hàng hoặc 7 ký tự cuối của ID giao dịch.\nChúng tôi sẽ phản hồi trong giờ làm việc.",
    'tl' => "Kumusta! 👋 Offline muna ang aming mga operator ngayon, pero natanggap namin ang iyong mensahe. May GPT StarPets consultant na tutulong sa iyo ngayon, at sasali ang operator kung kailangan.\n\nPakilarawan kung ano ang nangyari. Kung tungkol ito sa bayad, withdrawal, o order, puwede mo ring ipadala ang order ID o ang huling 7 character ng transaction ID.\nMakakabalik kami sa iyo sa oras ng trabaho.",
    'uk' => "Привіт! 👋 Зараз операторів немає на лінії, але ми отримали твоє повідомлення. Тобі допоможе GPT-консультант StarPets, а за потреби підключиться оператор.\n\nОпиши, будь ласка, що сталося. Якщо питання про оплату, виведення або замовлення — надішли ID замовлення або останні 7 символів ID транзакції.\nМи повернемося з відповіддю в робочий час.",
    'ur' => "سلام! 👋 ہمارے آپریٹرز ابھی آف لائن ہیں، لیکن ہمیں آپ کا پیغام مل گیا ہے۔ ابھی StarPets کا GPT کنسلٹنٹ آپ کی مدد کرے گا، اور ضرورت پڑنے پر آپریٹر شامل ہو جائے گا۔\n\nبراہ کرم بتائیں کیا ہوا۔ اگر معاملہ ادائیگی، رقم نکالنے یا آرڈر کا ہے تو آرڈر ID یا ٹرانزیکشن ID کے آخری 7 حروف بھی بھیج دیں۔\nہم کام کے اوقات میں آپ سے رابطہ کریں گے۔",
    'bn' => "হ্যালো! 👋 এই মুহূর্তে আমাদের অপারেটররা অফলাইনে আছেন, তবে আমরা আপনার বার্তা পেয়েছি। এখন StarPets-এর একজন GPT কনসালট্যান্ট আপনাকে সাহায্য করবে, প্রয়োজনে একজন অপারেটর যুক্ত হবেন।\n\nঅনুগ্রহ করে কী হয়েছে তা জানান। বিষয়টি পেমেন্ট, উইথড্রল বা অর্ডার সংক্রান্ত হলে অর্ডার ID বা ট্রানজেকশন ID-এর শেষ ৭টি অক্ষর পাঠাতে পারেন।\nকাজের সময়ের মধ্যে আমরা আপনাকে জবাব দেব।",
    'id' => "Hai! 👋 Operator kami sedang offline saat ini, tapi kami sudah menerima pesanmu. Konsultan GPT StarPets akan membantumu sekarang, dan operator akan ikut jika diperlukan.\n\nCeritakan apa yang terjadi. Jika ini soal pembayaran, penarikan, atau pesanan, kamu juga bisa mengirim ID pesanan atau 7 karakter terakhir dari ID transaksi.\nKami akan membalas pada jam kerja.",
    'pt_BR' => "Oi! 👋 Nossos operadores estão offline agora, mas recebemos sua mensagem. Um consultor GPT da StarPets vai te ajudar agora e, se precisar, um operador entra em ação.\n\nConta pra gente o que aconteceu. Se for sobre pagamento, saque ou pedido, você também pode enviar o ID do pedido ou os últimos 7 caracteres do ID da transação.\nVamos te responder no horário de trabalho."
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

  # Платформенные коды StarPets → языковые коды наших переводов (часть — коды стран).
  LOCALE_ALIASES = {
    'vn' => 'vi', 'ph' => 'tl', 'ua' => 'uk', 'uz' => 'ru', 'pk' => 'ur', 'bd' => 'bn',
    'es-mx' => 'es', 'es_mx' => 'es', 'pt-br' => 'pt_BR', 'pt_br' => 'pt_BR'
  }.freeze

  def conversation_language
    raw = (@conversation.contact&.custom_attributes&.dig('language').presence ||
           @conversation.additional_attributes&.dig('browser_language').presence).to_s.strip.downcase
    return nil if raw.blank?
    # известный алиас (vn→vi, es-mx→es, pt-br→pt_BR), иначе базовый код без региона
    (LOCALE_ALIASES[raw] || raw.split(/[-_]/).first).presence
  end
end
