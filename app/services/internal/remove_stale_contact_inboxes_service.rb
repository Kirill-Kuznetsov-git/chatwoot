class Internal::RemoveStaleContactInboxesService
  LOG_PREFIX = '[Internal::RemoveStaleContactInboxesService]'.freeze
  DEFAULT_RETENTION_DAYS = 90
  # Нижняя граница окна: за один прогон смотрим сессии возрастом от RETENTION до RETENTION+WINDOW дней.
  # Ежедневный запуск закрывает суточный срез с запасом в неделю; более старый хвост (после долгого
  # простоя джоба) чистится вручную — иначе каждый прогон перебирал бы всю историю сессий с диалогами.
  DEFAULT_WINDOW_DAYS = 7
  MIN_DAYS = 1
  BATCH_SIZE = 5_000
  # Предохранитель от бесконечного цикла: 10000 порций = 50M строк за прогон, остальное доберёт следующая ночь.
  MAX_BATCHES = 10_000

  def perform
    return unless remove_stale_contact_inbox_job_enabled?

    time_period = retention_days.days.ago
    window_start = time_period - window_days.days
    started_at = Time.current

    log_info("starting: removing contact inboxes without conversations created in [#{window_start}, #{time_period}) " \
             "(retention #{retention_days} days, window #{window_days} days)")

    total_deleted, batches = delete_in_batches(window_start, time_period)

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

  # Две короткие команды на порцию, каждая со своим коммитом (у воркера statement_timeout 14s, одна общая
  # транзакция на миллионы строк недопустима):
  #  1) выборка BATCH_SIZE строк только по индексу created_at с курсором — без join, поэтому останавливается
  #     на лимите и каждая строка читается один раз;
  #  2) DELETE по этим id, в котором условие «нет ни одного диалога» проверяется внутри самой команды, чтобы
  #     диалог, созданный между выборкой и удалением, сессию не потерял. Сессии с диалогами просто не удаляются.
  def delete_in_batches(window_start, time_period)
    total_deleted = 0
    batches = 0
    cursor = window_start

    while batches < MAX_BATCHES
      rows = candidate_rows(cursor, time_period)
      break if rows.empty?

      deleted = ContactInbox.where(id: rows.map(&:first)).stale_without_conversations(time_period).delete_all
      total_deleted += deleted
      batches += 1
      next_cursor = rows.last.second
      log_info("batch #{batches}: scanned #{rows.size}, deleted #{deleted} (total #{total_deleted}), cursor #{next_cursor}")
      # Неполная порция — диапазон исчерпан, дальше только сессии с диалогами из этой же порции.
      break if rows.size < BATCH_SIZE
      # Полная порция строк с одним и тем же created_at и все с диалогами — курсор не сдвинется, не крутиться на месте.
      break if next_cursor <= cursor && deleted.zero?

      cursor = next_cursor
    end

    [total_deleted, batches]
  end

  def candidate_rows(cursor, time_period)
    ContactInbox.where('contact_inboxes.created_at >= ? AND contact_inboxes.created_at < ?', cursor, time_period)
                .order('contact_inboxes.created_at ASC')
                .limit(BATCH_SIZE)
                .pluck(:id, :created_at)
  end

  # Срок хранения пустых сессий в днях из REMOVE_STALE_CONTACT_INBOX_DAYS (по умолчанию 90, как в upstream).
  def retention_days
    @retention_days ||= positive_days_from_env('REMOVE_STALE_CONTACT_INBOX_DAYS', DEFAULT_RETENTION_DAYS)
  end

  # Ширина окна в днях из REMOVE_STALE_CONTACT_INBOX_WINDOW_DAYS (по умолчанию 7).
  def window_days
    @window_days ||= positive_days_from_env('REMOVE_STALE_CONTACT_INBOX_WINDOW_DAYS', DEFAULT_WINDOW_DAYS)
  end

  # Значение меньше MIN_DAYS или не число — игнорируется с ошибкой в логе, чтобы опечатка
  # в конфиге не снесла живые сессии.
  def positive_days_from_env(name, default)
    raw = ENV.fetch(name, default.to_s)
    days = Integer(raw, exception: false)
    return days if days && days >= MIN_DAYS

    Rails.logger.error("#{LOG_PREFIX} invalid #{name}=#{raw.inspect}, falling back to #{default}")
    default
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
