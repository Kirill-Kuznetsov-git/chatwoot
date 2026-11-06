import { matchesFilters } from '../filterHelpers';

const filters = [
  {
    attribute_key: 'care_segment_weight',
    filter_operator: 'equal_to',
    values: ['Whale'],
    query_operator: null,
  },
];

describe('contact segments in conversation filters', () => {
  it('matches the paginated API segment rather than conversation custom attributes', () => {
    expect(
      matchesFilters(
        {
          care_segment: { weight: 'Whale' },
          custom_attributes: { care_segment_weight: 'Small Fish' },
        },
        filters
      )
    ).toBe(true);
    expect(
      matchesFilters(
        {
          care_segment: { weight: 'Small Fish' },
          custom_attributes: { care_segment_weight: 'Whale' },
        },
        filters
      )
    ).toBe(false);
  });

  it('prefers fresh sender attributes over stale list metadata in realtime events', () => {
    const conversation = {
      care_segment: { weight: 'Small Fish' },
      meta: { sender: { custom_attributes: { segment_weight: 'Whale' } } },
    };
    expect(matchesFilters(conversation, filters)).toBe(true);
    conversation.meta.sender.custom_attributes = {};
    conversation.care_segment.weight = 'Whale';
    expect(matchesFilters(conversation, filters)).toBe(false);
  });

  it('handles camel-case list metadata and combines role and status', () => {
    const combined = [
      { ...filters[0], query_operator: 'and' },
      {
        attribute_key: 'care_segment_role',
        filter_operator: 'equal_to',
        values: [{ id: 'Seller', name: 'Seller' }],
        query_operator: 'and',
      },
      {
        attribute_key: 'status',
        filter_operator: 'equal_to',
        values: ['open'],
        query_operator: null,
      },
    ];
    expect(
      matchesFilters(
        { status: 'open', careSegment: { weight: 'Whale', role: 'Seller' } },
        combined
      )
    ).toBe(true);
    expect(
      matchesFilters(
        { status: 'pending', careSegment: { weight: 'Whale', role: 'Seller' } },
        combined
      )
    ).toBe(false);
  });

  it('includes contacts without a segment in not equal to like SQL', () => {
    expect(
      matchesFilters({}, [{ ...filters[0], filter_operator: 'not_equal_to' }])
    ).toBe(true);
  });
});
