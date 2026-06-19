# Translates arbitrary text into a target language using the same ruby_llm /
# OpenAI stack as the Captain/AI-Assist features. Reuses the account's OpenAI
# integration api_key (falls back to the installation-level Captain key).
# Returns the translated string, or nil on any failure (callers must fall back
# to the original text — translation must never drop a message).
class Integrations::Openai::TranslateService
  pattr_initialize [:account!, :content!, :target_language!]

  MODEL = ENV.fetch('AUTO_TRANSLATE_MODEL', Llm::Config::DEFAULT_MODEL)

  def perform
    return if content.blank? || target_language.blank?
    return if api_key.blank?

    Llm::Config.with_api_key(api_key, api_base: api_base) do |context|
      chat = context.chat(model: MODEL)
      chat.with_instructions(system_prompt)
      chat.ask(content).content
    end
  rescue StandardError => e
    Rails.logger.error("[OpenaiTranslate] #{e.class}: #{e.message}")
    nil
  end

  private

  def system_prompt
    "You are a professional translator for a customer-support chat. " \
      "Translate the user's message into #{target_language}. " \
      "Preserve meaning, tone, emoji, markdown, URLs and placeholders. " \
      "Do NOT translate usernames, order IDs or code. " \
      'Output ONLY the translation — no preamble, no quotes, no notes.'
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
