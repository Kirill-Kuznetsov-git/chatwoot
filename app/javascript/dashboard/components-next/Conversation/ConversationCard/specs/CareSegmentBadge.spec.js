import { mount } from '@vue/test-utils';
import CareSegmentBadge from '../CareSegmentBadge.vue';

const mountBadge = props =>
  mount(CareSegmentBadge, {
    props,
    global: {
      directives: { tooltip: {} },
    },
  });

describe('CareSegmentBadge', () => {
  it('shows the weight emoji for valuable customers', () => {
    const wrapper = mountBadge({
      contact: {
        customAttributes: {
          segmentLabel: '🐋 Big Whale Seller',
          segmentWeight: 'Big Whale',
        },
      },
    });

    expect(wrapper.text()).toBe('🐋');
  });

  it('reads snake_case attributes too, since the payload is not always transformed', () => {
    const wrapper = mountBadge({
      contact: {
        customAttributes: {
          segment_label: '🦈 Whale Buyer',
          segment_weight: 'Whale',
        },
      },
    });

    expect(wrapper.text()).toBe('🦈');
  });

  it('falls back to the sender on the conversation when the contact is not loaded yet', () => {
    const wrapper = mountBadge({
      contact: {},
      conversation: {
        meta: {
          sender: {
            customAttributes: {
              segmentLabel: '🐳 Mega Whale Trader',
              segmentWeight: 'Mega Whale',
            },
          },
        },
      },
    });

    expect(wrapper.text()).toBe('🐳');
  });

  it('shows the badge for the Big tier regardless of lifetime weight', () => {
    const wrapper = mountBadge({
      contact: {
        customAttributes: {
          segmentLabel: '🐠 Mid Fish Buyer',
          segmentWeight: 'Mid Fish',
          segmentTier90d: 'Big',
        },
      },
    });

    expect(wrapper.text()).toBe('🐠');
  });

  it('stays out of the way for ordinary and unsegmented customers', () => {
    const ordinary = mountBadge({
      contact: {
        customAttributes: {
          segmentLabel: '🌊 No Purchases Newcomer',
          segmentWeight: 'No Purchases',
        },
      },
    });
    const unknown = mountBadge({ contact: {}, conversation: {} });

    expect(ordinary.text()).toBe('');
    expect(unknown.text()).toBe('');
  });

  it('renders nothing when the label carries no emoji', () => {
    const wrapper = mountBadge({
      contact: {
        customAttributes: {
          segmentLabel: 'Whale Buyer',
          segmentWeight: 'Whale',
        },
      },
    });

    expect(wrapper.text()).toBe('');
  });
});
