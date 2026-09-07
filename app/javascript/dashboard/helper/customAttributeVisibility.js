// Служебные атрибуты (например segment_priority из Support Care) нужны автоматизациям и
// фильтрам, но операторов только путают. Определение, чьё описание начинается с [hidden],
// не рисуется в карточке контакта; в настройках атрибутов и в условиях автоматизаций оно
// остаётся видимым. Работает и с camelCase (store getters), и со snake_case (сырой API).
export const HIDDEN_MARKER = '[hidden]';

export const isHiddenCustomAttribute = attribute => {
  const description =
    attribute?.attributeDescription ?? attribute?.attribute_description ?? '';
  return String(description).trim().toLowerCase().startsWith(HIDDEN_MARKER);
};

export const visibleCustomAttributes = (attributes = []) =>
  (attributes || []).filter(attribute => !isHiddenCustomAttribute(attribute));
