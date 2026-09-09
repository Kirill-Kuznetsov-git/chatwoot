import { mount } from '@vue/test-utils';
import CareSegmentBadge from '../CareSegmentBadge.vue';

const mountBadge = conversation =>
  mount(CareSegmentBadge, {
    props: { conversation },
    global: {
      directives: { tooltip: {} },
      mocks: { $t: key => key },
    },
  });

describe('CareSegmentBadge', () => {
  it('shows the role letter for the biggest customers', () => {
    const wrapper = mountBadge({
      careSegment: {
        label: '\u{1F433} Mega Whale Trader',
        weight: 'Mega Whale',
        role: 'Trader',
        tier90d: 'Big',
      },
    });

    expect(wrapper.text()).toBe('T');
    expect(wrapper.classes()).toContain('bg-n-iris-9');
  });

  it('paints each weight in its own colour', () => {
    const colours = {
      'Big Whale': 'bg-n-blue-9',
      Whale: 'bg-n-teal-9',
      'Big Fish': 'bg-n-slate-4',
    };
    Object.entries(colours).forEach(([weight, cls]) => {
      const wrapper = mountBadge({ careSegment: { weight, role: 'Buyer' } });
      expect(wrapper.text()).toBe('B');
      expect(wrapper.classes()).toContain(cls);
    });
  });

  it('reads the snake_case payload too', () => {
    const wrapper = mountBadge({
      care_segment: { weight: 'Whale', role: 'Seller', tier_90d: 'Small' },
    });

    expect(wrapper.text()).toBe('S');
  });

  it('keeps an active mid-tier customer visible through the 90-day tier', () => {
    const wrapper = mountBadge({
      careSegment: { weight: 'Mid Fish', role: 'Seller', tier90d: 'Big' },
    });

    expect(wrapper.text()).toBe('S');
    expect(wrapper.classes()).toContain('bg-n-slate-4');
  });

  it('stays out of the way for ordinary and unsegmented customers', () => {
    const ordinary = mountBadge({
      careSegment: {
        weight: 'No Purchases',
        role: 'Newcomer',
        tier90d: 'Small',
      },
    });

    expect(ordinary.text()).toBe('');
    expect(mountBadge({}).text()).toBe('');
  });

  it('falls back to a neutral marker when the role is unknown', () => {
    const wrapper = mountBadge({ careSegment: { weight: 'Whale' } });
    expect(wrapper.text()).toBe('\u2022');
  });
});
