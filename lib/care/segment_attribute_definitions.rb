# Определения атрибутов сегмента на контакте (CustomAttributeDefinition, attribute_model =
# contact_attribute). Без них значения в jsonb всё равно пишутся, но не видны в карточке
# контакта и недоступны как условия в фильтрах/автоматизациях. Идемпотентно.
#
# Служебные поля (priority, synced_at) помечены [hidden] в описании: дашборд их в карточке
# контакта не рисует (dashboard/helper/customAttributeVisibility.js), но для автоматизаций
# и фильтров они остаются.
module Care::SegmentAttributeDefinitions
  HIDDEN = '[hidden] '.freeze

  DEFINITIONS = [
    { key: 'segment_label', name: 'Segment', type: 'text',
      description: 'Сегмент из Support Care: вес за всё время + роль, напр. «🐋 Big Whale Seller»' },
    { key: 'segment_role', name: 'Segment role', type: 'list', values: %w[Buyer Seller Trader Newcomer],
      description: 'Как клиент использует платформу (по покупкам и продажам за всё время)' },
    { key: 'segment_weight', name: 'Segment weight', type: 'list',
      values: ['Mega Whale', 'Big Whale', 'Whale', 'Big Fish', 'Mid Fish', 'Small Fish', 'No Purchases'],
      description: 'Значимость по обороту за всё время' },
    { key: 'segment_tier_90d', name: 'Segment tier (90d)', type: 'list', values: %w[Big Medium Small],
      description: 'Активность за 90 дней внутри роли: топ-10 % / до медианы / остальные и неактивные' },
    { key: 'segment_priority', name: 'Segment priority', type: 'number',
      description: "#{HIDDEN}Ранг для очередей и автоматизаций: меньше — важнее (вес × 10 + tier); 0 = Mega Whale Big" },
    { key: 'segment_synced_at', name: 'Segment synced at', type: 'date',
      description: "#{HIDDEN}Когда сегмент последний раз подтянут из Support Care" }
  ].freeze

  # Создаёт недостающие определения и подтягивает описания у существующих наших ключей
  # (описание — носитель пометки [hidden]). Имена, типы и значения существующих не трогает.
  # => { created: [ключи], updated: [ключи] }
  def self.ensure!(account)
    result = { created: [], updated: [] }
    DEFINITIONS.each do |definition|
      existing = account.custom_attribute_definitions.with_attribute_model('contact_attribute')
                        .find_by(attribute_key: definition[:key])
      if existing.nil?
        create_definition(account, definition)
        result[:created] << definition[:key]
      elsif existing.attribute_description != definition[:description]
        existing.update!(attribute_description: definition[:description])
        result[:updated] << definition[:key]
      end
    end
    result
  end

  def self.create_definition(account, definition)
    account.custom_attribute_definitions.create!(
      attribute_model: 'contact_attribute',
      attribute_key: definition[:key],
      attribute_display_name: definition[:name],
      attribute_display_type: definition[:type],
      attribute_values: definition[:values] || [],
      attribute_description: definition[:description]
    )
  end
end
