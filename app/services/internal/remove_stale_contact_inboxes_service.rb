class Internal::RemoveStaleContactInboxesService
  LOG_PREFIX = '[Internal::RemoveStaleContactInboxesService]'.freeze
  DEFAULT_RETENTION_DAYS = 90
  MIN_RETENTION_DAYS = 1
  BATCH_SIZE = 10_000
  # Предохранитель от бесконечного цикла: 5000 порций = 50M строк за прогон, остальное доберёт следующая ночь.
  MAX_BATCHES = 5_000

  def perform
    return unless remove_stale_contact_inbox_job_enabled?

    time_period = retention_days.days.ago
    started_at = Time.current
    total_deleted = 0
    batches = 0

    log_info("starting: removing contact inboxes without conversations created before #{time_period} (#{retention_days} days)")

    # Каждая порция — отдельная короткая команда со своим коммитом (у воркера statement_timeout 14s,
    # одна общая транзакция на миллионы строк недопустима). Кандидаты берутся через индекс по created_at,
    # а условие «нет ни одного диалога» повторно проверяется внутри самой команды DELETE, чтобы диалог,
    # созданный между выборкой и удалением, сессию не потерял.
    while batches < MAX_BATCHES
      ids = ContactInbox.stale_without_conversations(time_period).limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      deleted = ContactInbox.where(id: ids).stale_without_conversations(time_period).delete_all
      total_deleted += deleted
      batches += 1
      log_info("batch #{batches}: deleted #{deleted} (total #{total_deleted})")
      # Ничего не удалилось — у всех кандидатов за миг появились диалоги; не крутиться, доберём завтра.
      break if deleted.zero?
    end

    log_info("finished: deleted #{total_deleted} contact inboxes in #{batches} batches, #{(Time.current - started_at).round(1)}s")
    check_orphan_conversations
    total_deleted
  end

  private

  def remove_stale_contact_inbox_job_enabled?
    job_status = ENV.fetch('REMOVE_STALE_CONTACT_INBOX_JOB_STATUS', false)
    return false unless ActiveModel::Type::Boolean.new.cast(job_status)

    true
  end

  # Срок хранения пустых сессий в днях из REMOVE_STALE_CONTACT_INBOX_DAYS (по умолчанию 90, как в upstream).
  # Значение меньше MIN_RETENTION_DAYS или не число — игнорируется с ошибкой в логе, чтобы опечатка
  # в конфиге не снесла живые сессии.
  def retention_days
    @retention_days ||= begin
      raw = ENV.fetch('REMOVE_STALE_CONTACT_INBOX_DAYS', DEFAULT_RETENTION_DAYS.to_s)
      days = Integer(raw, exception: false)
      if days.nil? || days < MIN_RETENTION_DAYS
        Rails.logger.error("#{LOG_PREFIX} invalid REMOVE_STALE_CONTACT_INBOX_DAYS=#{raw.inspect}, falling back to #{DEFAULT_RETENTION_DAYS}")
        DEFAULT_RETENTION_DAYS
      else
        days
      end
    end
  end

  # Диалог без сессии — признак гонки «сессия удалена в момент отправки первого сообщения».
  # Считаем после каждого прогона, чтобы заметить сразу, а не через месяц.
  def check_orphan_conversations
    orphans = Conversation.where.missing(:contact_inbox).count
    return log_info('orphan check: 0 conversations without contact inbox') if orphans.zero?

    Rails.logger.warn("#{LOG_PREFIX} orphan check: #{orphans} conversations without contact inbox")
  end

  def log_info(message)
    Rails.logger.info("#{LOG_PREFIX} #{message}")
  end
end
