# Определения атрибутов сегмента на контакте (CustomAttributeDefinition, attribute_model =
# contact_attribute). Без них значения в jsonb всё равно пишутся, но не видны в карточке
# контакта и недоступны как условия в фильтрах/автоматизациях. Идемпотентно.
module Care::SegmentAttributeDefinitions
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
      description: 'Ранг для очередей: меньше — важнее (вес × 10 + tier); 0 = Mega Whale Big' },
    { key: 'segment_synced_at', name: 'Segment synced at', type: 'date',
      description: 'Когда сегмент последний раз подтянут из Support Care' }
  ].freeze

  # Создаёт недостающие определения. Возвращает ключи созданных.
  def self.ensure!(account)
    DEFINITIONS.filter_map do |definition|
      next if account.custom_attribute_definitions.with_attribute_model('contact_attribute')
                     .exists?(attribute_key: definition[:key])

      account.custom_attribute_definitions.create!(
        attribute_model: 'contact_attribute',
        attribute_key: definition[:key],
        attribute_display_name: definition[:name],
        attribute_display_type: definition[:type],
        attribute_values: definition[:values] || [],
        attribute_description: definition[:description]
      )
      definition[:key]
    end
  end
end
