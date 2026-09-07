# Гарантирует Label-записи аккаунта для лейблов очереди и SLA. acts_as_taggable сам записи Label не создаёт,
# а без них лейбл не виден в сайдбаре и фильтрах — операторы и лиды не смогут по нему отобрать диалоги.
module Care::Queue::Labels
  COLORS = { 'vip' => '#F59E0B', 'sla-risk' => '#F97316', 'sla-breach' => '#EF4444' }.freeze
  DEFAULT_COLOR = '#1F93FF'.freeze

  def self.ensure!(account, titles)
    titles = Array(titles).compact_blank.uniq
    return [] if titles.empty?

    existing = account.labels.where(title: titles).pluck(:title)
    (titles - existing).filter_map do |title|
      account.labels.create!(title: title, color: COLORS.fetch(title, DEFAULT_COLOR), show_on_sidebar: true)
      title
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      # гонка двух тиков или чужой лейбл с тем же названием — лейбл всё равно есть
      Rails.logger.warn("Care::Queue::Labels: #{title} не создан (#{e.class}: #{e.message})")
      nil
    end
  end
end
