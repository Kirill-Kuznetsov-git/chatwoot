# Бэкфилл сегмента для ценных контактов (SCC-100, этап 1). Care отдаёт user_id китов и Big
# за 90 дней страницами; здесь ищем эти id среди identifier контактов аккаунта и синхронно
# гоняем Care::SegmentSyncJob с ограничением скорости. Никаких очередей — прогресс виден в
# логе, остановка = остановить one-off dyno, продолжение = --after_id из последней строки лога.
class Care::SegmentBackfill
  Result = Struct.new(:pages, :ids_seen, :contacts_found, :synced, :changed, :skipped_fresh, :failed, :last_after_id,
                      keyword_init: true)

  # options: rate_per_minute (300), page_size (1000), dry_run (false), sleeper (lambda для тестов)
  def initialize(account:, client: Care::Client.new, logger: Rails.logger, **options)
    @account = account
    @client = client
    @logger = logger
    rate = options.fetch(:rate_per_minute, 300)
    @delay = rate.positive? ? 60.0 / rate : 0
    @page_size = options.fetch(:page_size, 1000)
    @dry_run = options.fetch(:dry_run, false)
    @sleeper = options.fetch(:sleeper, ->(seconds) { sleep(seconds) })
  end

  def run(after_id: nil)
    result = Result.new(pages: 0, ids_seen: 0, contacts_found: 0, synced: 0, changed: 0, skipped_fresh: 0, failed: 0,
                        last_after_id: after_id)
    loop do
      page = @client.valuable_user_ids(after_id: after_id, limit: @page_size)
      ids = page['user_ids']
      result.pages += 1
      result.ids_seen += ids.size
      process_page(ids, result) if ids.any?
      after_id = page['next_after_id']
      result.last_after_id = ids.last if ids.any?
      log(result, page['total'])
      break if after_id.blank?
    end
    result
  end

  private

  def process_page(ids, result)
    # контакты целиком: update! внутри apply! гоняет валидации, частичный select их ломает
    @account.contacts.where(identifier: ids).find_each do |contact|
      result.contacts_found += 1
      if Care::SegmentSync.fresh?(contact)
        result.skipped_fresh += 1
        next
      end
      next if @dry_run

      sync(contact, result)
      @sleeper.call(@delay) if @delay.positive?
    end
  end

  # Ошибки Care не должны валить весь прогон — считаем и идём дальше.
  def sync(contact, result)
    changed = Care::SegmentSync.sync_contact!(contact, client: @client)
    result.synced += 1
    result.changed += 1 if changed
  rescue Care::Client::Error => e
    result.failed += 1
    @logger.warn("Care::SegmentBackfill: contact #{contact.id} failed: #{e.class}: #{e.message}")
    @sleeper.call(@delay * 5) if e.is_a?(Care::Client::Unavailable) && @delay.positive?
  end

  def log(result, total)
    @logger.info("Care::SegmentBackfill#{' [dry-run]' if @dry_run}: page #{result.pages}, ids #{result.ids_seen}/#{total}, " \
                 "contacts #{result.contacts_found}, synced #{result.synced} (changed #{result.changed}), " \
                 "fresh-skipped #{result.skipped_fresh}, failed #{result.failed}, after_id=#{result.last_after_id}")
  end
end
