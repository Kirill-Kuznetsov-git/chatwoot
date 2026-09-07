# Утренний досинк (SCC-100): Care ночью пересчитал сегменты и пометил изменившихся; здесь берём их
# список, находим такие контакты и ставим им принудительный синк. Тысячи задач, не миллионы —
# в Redis это безопасно. Расписание — config/schedule.yml (после ночного прогона Care в 01:00 UTC).
class Care::SegmentResyncChangedJob < ApplicationJob
  queue_as :low

  LOOKBACK = 26.hours
  PAGE_SIZE = 1000
  MAX_PAGES = 5_000

  def perform(since = nil)
    return unless Care::SegmentSync.enabled?

    since = since.present? ? Time.zone.parse(since.to_s) : LOOKBACK.ago
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
    Rails.logger.info("Care::SegmentResyncChangedJob since=#{since.utc.iso8601}: #{stats}")
    stats
  end

  private

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
