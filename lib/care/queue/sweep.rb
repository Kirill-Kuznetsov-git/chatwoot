# Страховка тика: открытые диалоги классифицируемых контактов без активного трекера. Ловит пропущенные
# события, диалоги, открытые до включения фичи (бэкфилл), и расширение конфига (класс вернулся).
# Отбор классифицируемых — в SQL по текущему конфигу, чтобы лимит не съели диалоги вне очереди.
class Care::Queue::Sweep
  LIMIT = 300
  LOOKBACK = 30.days

  def initialize(config:, limit: LIMIT, now: Time.current)
    @config = config
    @limit = limit
    @now = now
  end

  # => сколько диалогов получили трекер
  def call
    return 0 if @config.classes.empty?

    count = 0
    scope.each do |conversation|
      tracker = Care::Queue::Applier.apply!(conversation, config: @config, now: @now, started_at: handoff_at(conversation))
      count += 1 if tracker
    rescue StandardError => e
      Rails.logger.error("Care::Queue::Sweep conversation #{conversation.id}: #{e.class}: #{e.message}")
    end
    count
  end

  private

  def scope
    scope = Conversation.open.joins(:contact)
                        .where(@config.contact_match_sql)
                        .where('conversations.created_at > ?', @now - LOOKBACK)
                        .where.not(id: Care::SlaTracker.active.select(:conversation_id))
    account_id = ENV.fetch('CARE_SEGMENT_SYNC_ACCOUNT_ID', nil)
    scope = scope.where(account_id: account_id.to_i) if account_id.present?
    scope.order(:id).limit(@limit)
  end

  # Старт часов — передача человеку (событие bot_handoff), для инбоксов без бота — создание диалога.
  def handoff_at(conversation)
    ReportingEvent.where(conversation_id: conversation.id, name: 'conversation_bot_handoff').minimum(:created_at) ||
      conversation.created_at
  end
end
