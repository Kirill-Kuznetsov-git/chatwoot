import { mount } from '@vue/test-utils';
import CareSegmentBadge from '../CareSegmentBadge.vue';

const mountBadge = conversation =>
  mount(CareSegmentBadge, {
    props: { conversation },
    global: {
      directives: { tooltip: {} },
    },
  });

describe('CareSegmentBadge', () => {
  it('shows the weight emoji for valuable customers', () => {
    const wrapper = mountBadge({
      careSegment: { label: '🐋 Big Whale Seller', weight: 'Big Whale' },
    });

    expect(wrapper.text()).toBe('🐋');
  });

  it('reads the snake_case payload too', () => {
    const wrapper = mountBadge({
      care_segment: {
        label: '🦈 Whale Buyer',
        weight: 'Whale',
        tier_90d: 'Small',
      },
    });

    expect(wrapper.text()).toBe('🦈');
  });

  it('shows the badge for the Big tier regardless of lifetime weight', () => {
    const wrapper = mountBadge({
      careSegment: {
        label: '🐠 Mid Fish Buyer',
        weight: 'Mid Fish',
        tier90d: 'Big',
      },
    });

    expect(wrapper.text()).toBe('🐠');
  });

  it('stays out of the way for ordinary and unsegmented customers', () => {
    const ordinary = mountBadge({
      careSegment: {
        label: '🌊 No Purchases Newcomer',
        weight: 'No Purchases',
        tier90d: 'Small',
      },
    });

    expect(ordinary.text()).toBe('');
    expect(mountBadge({}).text()).toBe('');
  });

  it('renders nothing when the label carries no emoji', () => {
    const wrapper = mountBadge({
      careSegment: { label: 'Whale Buyer', weight: 'Whale' },
    });

    expect(wrapper.text()).toBe('');
  });
});
