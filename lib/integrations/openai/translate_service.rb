# Translates arbitrary text into a target language using the same ruby_llm /
# OpenAI stack as the Captain/AI-Assist features. Reuses the account's OpenAI
# integration api_key (falls back to the installation-level Captain key).
# Returns the translated string, or nil on a PERMANENT failure (callers fall
# back to the original text — translation must never drop a message). Transient
# failures (rate limit, 5xx, network) raise TransientError so the job retries.
class Integrations::Openai::TranslateService
  pattr_initialize [:account!, :content!, :target_language!]

  MODEL = ENV.fetch('AUTO_TRANSLATE_MODEL', Llm::Config::DEFAULT_MODEL)

  # Названия языков для промпта: модели приходит имя, а не код локали. Список —
  # локали интерфейса Chatwoot; незнакомый код уходит как есть.
  LANGUAGE_NAMES = {
    'ar' => 'Arabic', 'ca' => 'Catalan', 'cs' => 'Czech', 'da' => 'Danish',
    'de' => 'German', 'el' => 'Greek', 'en' => 'English', 'es' => 'Spanish',
    'fa' => 'Persian', 'fi' => 'Finnish', 'fr' => 'French', 'he' => 'Hebrew',
    'hi' => 'Hindi', 'hu' => 'Hungarian', 'id' => 'Indonesian', 'it' => 'Italian',
    'ja' => 'Japanese', 'ko' => 'Korean', 'lt' => 'Lithuanian', 'lv' => 'Latvian',
    'ml' => 'Malayalam', 'nl' => 'Dutch', 'no' => 'Norwegian', 'pl' => 'Polish',
    'pt' => 'Portuguese', 'pt_BR' => 'Brazilian Portuguese', 'ro' => 'Romanian',
    'ru' => 'Russian', 'sk' => 'Slovak', 'sv' => 'Swedish', 'ta' => 'Tamil',
    'th' => 'Thai', 'tr' => 'Turkish', 'uk' => 'Ukrainian', 'vi' => 'Vietnamese',
    'zh' => 'Chinese', 'zh_CN' => 'Simplified Chinese', 'zh_TW' => 'Traditional Chinese'
  }.freeze

  # Raised on transient upstream failures so the enqueuing job can retry.
  TransientError = Class.new(StandardError)

  def perform
    return if content.blank? || target_language.blank?
    return if api_key.blank?

    Llm::Config.with_api_key(api_key, api_base: api_base) do |context|
      chat = context.chat(model: MODEL)
      chat.with_instructions(system_prompt)
      chat.ask(content).content
    end
  rescue RubyLLM::RateLimitError, RubyLLM::ServerError, RubyLLM::ServiceUnavailableError,
         RubyLLM::OverloadedError, Faraday::TimeoutError, Faraday::ConnectionFailed => e
    Rails.logger.warn("[OpenaiTranslate] transient #{e.class}: #{e.message} — retrying")
    raise TransientError, "#{e.class}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error("[OpenaiTranslate] #{e.class}: #{e.message}")
    nil
  end

  private

  # Сообщение уже на языке оператора — обычный случай, а не исключение: оператор
  # и клиент часто пишут на одном языке. Прежняя формулировка «translate into X»
  # в этом случае заставляла модель перевести хоть куда-нибудь, и русское
  # «работа» превращалось в английское «work». Поэтому язык называется словом, а
  # совпадение языков описано явно как «верни без изменений».
  def system_prompt
    "You translate customer-support messages into #{language_name} and into no other " \
      "language. If the message is already written in #{language_name}, output it back " \
      'completely unchanged, character for character, and translate nothing. Otherwise ' \
      "output its #{language_name} translation. " \
      'Preserve meaning, tone, emoji, markdown, URLs and placeholders. ' \
      'Do NOT translate usernames, order IDs or code. ' \
      'Output ONLY the resulting text — no preamble, no quotes, no notes.'
  end

  def language_name
    LANGUAGE_NAMES[target_language.to_s] || target_language
  end

  def api_key
    @api_key ||= account.hooks.find_by(app_id: 'openai')&.settings&.dig('api_key').presence ||
                 InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end

  def api_base
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com/'
    "#{endpoint.chomp('/')}/v1"
  end
end
