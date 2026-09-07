import {
  isHiddenCustomAttribute,
  visibleCustomAttributes,
} from '../customAttributeVisibility';

describe('customAttributeVisibility', () => {
  it('hides attributes whose description starts with [hidden] in any case and with spaces', () => {
    expect(
      isHiddenCustomAttribute({
        attributeDescription: '[hidden] Ранг для очередей',
      })
    ).toBe(true);
    expect(
      isHiddenCustomAttribute({ attribute_description: '  [HIDDEN] synced at' })
    ).toBe(true);
  });

  it('keeps attributes without the marker, with the marker elsewhere, or without description', () => {
    expect(isHiddenCustomAttribute({ attributeDescription: 'Сегмент' })).toBe(
      false
    );
    expect(
      isHiddenCustomAttribute({ attributeDescription: 'не [hidden] в начале' })
    ).toBe(false);
    expect(isHiddenCustomAttribute({ attributeDescription: null })).toBe(false);
    expect(isHiddenCustomAttribute({})).toBe(false);
    expect(isHiddenCustomAttribute(undefined)).toBe(false);
  });

  it('filters a list and tolerates empty input', () => {
    const list = [
      { attributeKey: 'segment_label', attributeDescription: 'Сегмент' },
      {
        attributeKey: 'segment_priority',
        attributeDescription: '[hidden] ранг',
      },
      { attribute_key: 'starpets_id' },
    ];
    expect(
      visibleCustomAttributes(list).map(a => a.attributeKey || a.attribute_key)
    ).toEqual(['segment_label', 'starpets_id']);
    expect(visibleCustomAttributes()).toEqual([]);
    expect(visibleCustomAttributes(null)).toEqual([]);
  });
});
