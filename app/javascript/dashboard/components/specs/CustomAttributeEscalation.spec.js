import { mount } from '@vue/test-utils';
import CustomAttribute from '../CustomAttribute.vue';

describe('CustomAttribute escalation title', () => {
  it('can explicitly clear an optional override so the server restores the automatic topic', async () => {
    const wrapper = mount(CustomAttribute, {
      props: {
        label: 'Slack title',
        attributeKey: 'manual_escalation_title',
        value: 'Manual',
        allowEmpty: true,
      },
      global: {
        directives: { 'on-clickaway': {} },
        mocks: { $t: key => key },
        stubs: {
          HelperTextPopup: true,
          MultiselectDropdown: true,
          NextButton: true,
        },
      },
    });
    wrapper.vm.editedValue = '';
    await wrapper.vm.onUpdate();
    expect(wrapper.emitted('update')).toEqual([
      ['manual_escalation_title', ''],
    ]);
  });
});
