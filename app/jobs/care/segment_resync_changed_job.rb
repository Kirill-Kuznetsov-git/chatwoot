# Утренний досинк (SCC-100): Care ночью пересчитал сегменты и пометил изменившихся; здесь берём их
# список, находим такие контакты и ставим им принудительный синк. Тысячи задач, не миллионы —
# в Redis это безопасно.
#
# Расписание — config/schedule.yml, каждый час. Сам джоб решает, пора ли: если последний успешный
# прогон был меньше MIN_INTERVAL назад, выходим сразу. Так пропуск конкретного часа (суточный рестарт
# дино на Heroku съел запуск 08.09) не оставляет сегменты в Chatwoot неактуальными на сутки — прогон
# просто случится часом позже. Окно берём от последнего успеха, чтобы не терять изменения в пропуске.
class Care::SegmentResyncChangedJob < ApplicationJob
  queue_as :low

  LAST_SUCCESS_KEY = 'care:segment_resync:last_success'.freeze
  MIN_INTERVAL = 20.hours
  LOOKBACK = 26.hours
  MAX_LOOKBACK = 7.days
  PAGE_SIZE = 1000
  MAX_PAGES = 5_000

  # since — явное начало окна (rake, ручной догон); force — прогнать, не глядя на отметку.
  def perform(since = nil, force: false)
    return unless Care::SegmentSync.enabled?

    last_success = read_last_success
    return if !force && since.blank? && last_success.present? && last_success > MIN_INTERVAL.ago

    since = window_start(since, last_success)
    stats = fetch_and_enqueue(since)
    Redis::Alfred.set(LAST_SUCCESS_KEY, Time.current.utc.iso8601)
    Rails.logger.info("Care::SegmentResyncChangedJob since=#{since.utc.iso8601}: #{stats}")
    stats
  end

  private

  def read_last_success
    raw = Redis::Alfred.get(LAST_SUCCESS_KEY)
    raw.present? ? Time.zone.parse(raw) : nil
  rescue ArgumentError
    nil
  end

  # От последнего успеха (чтобы догнать пропущенное), но не глубже MAX_LOOKBACK — иначе после долгого
  # простоя один прогон поставил бы сотни тысяч задач.
  def window_start(since, last_success)
    start = since.present? ? Time.zone.parse(since.to_s) : (last_success || LOOKBACK.ago)
    [start, MAX_LOOKBACK.ago].max
  end

  def fetch_and_enqueue(since)
    client = Care::Client.new
    stats = { pages: 0, ids: 0, contacts: 0 }
    after_id = nil
    loop do
      page = client.changed_user_ids(since: since, after_id: after_id, limit: PAGE_SIZE)
      stats[:pages] += 1
      stats[:ids] += page['user_ids'].size
      stats[:contacts] += enqueue_for(page['user_ids'])
      after_id = page['next_after_id']
      break if after_id.blank? || stats[:pages] >= MAX_PAGES
    end
    stats
  end

  def enqueue_for(user_ids)
    return 0 if user_ids.empty?

    scope = Contact.where(identifier: user_ids)
    account_id = ENV.fetch('CARE_SEGMENT_SYNC_ACCOUNT_ID', nil)
    scope = scope.where(account_id: account_id.to_i) if account_id.present?
    ids = scope.pluck(:id)
    ids.each { |contact_id| Care::SegmentSyncJob.perform_later(contact_id, force: true) }
    ids.size
  end
end
