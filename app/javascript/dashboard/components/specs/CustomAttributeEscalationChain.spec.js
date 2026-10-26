import { computed, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useRoute } from 'vue-router';
import actions from 'dashboard/store/modules/conversations/actions';
import CustomAttributes from 'dashboard/routes/dashboard/conversation/customAttributes/CustomAttributes.vue';
import CustomAttribute from '../CustomAttribute.vue';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useUISettings');
vi.mock('vue-router');
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

it('sends an empty native title from the actual input through the sidebar and Vuex action to HTTP', async () => {
  const commit = vi.fn();
  const responseAttributes = {
    manual_escalation_title: '',
    manual_escalation_reason: 'Другое',
  };
  global.axios = {
    post: vi
      .fn()
      .mockResolvedValue({ data: { custom_attributes: responseAttributes } }),
  };
  const store = {
    getters: reactive({
      getSelectedChat: {
        id: 1,
        custom_attributes: {
          manual_escalation_title: 'Manual',
          manual_escalation_reason: 'Другое',
        },
      },
      'attributes/getAttributesByModel': () => [
        {
          id: 1,
          attribute_key: 'manual_escalation_title',
          attribute_display_name: 'Slack title',
          attribute_display_type: 'text',
        },
      ],
    }),
    dispatch: vi.fn((name, values) => actions[name]({ commit }, values)),
  };
  useStore.mockReturnValue(store);
  useStoreGetters.mockReturnValue(
    Object.fromEntries(
      Object.keys(store.getters).map(key => [
        key,
        computed(() => store.getters[key]),
      ])
    )
  );
  useRoute.mockReturnValue({ params: {} });
  useUISettings.mockReturnValue({
    uiSettings: ref({}),
    updateUISettings: vi.fn(),
  });
  const wrapper = mount(CustomAttributes, {
    props: { attributeFrom: 'conversation' },
    global: {
      directives: { 'on-clickaway': {} },
      stubs: {
        Draggable: {
          props: ['list'],
          template:
            '<div><template v-for="element in list"><slot name="item" :element="element" /></template></div>',
        },
        HelperTextPopup: true,
        MultiselectDropdown: true,
      },
    },
  });
  await wrapper.findComponent(CustomAttribute).vm.onEdit();
  await wrapper.find('input').setValue('');
  await wrapper.find('input').trigger('keyup.enter');
  await flushPromises();
  expect(global.axios.post).toHaveBeenCalledWith(
    expect.stringContaining('/1/custom_attributes'),
    { custom_attributes: responseAttributes }
  );
  expect(commit).toHaveBeenCalledWith(expect.any(String), {
    conversationId: 1,
    customAttributes: responseAttributes,
  });
  wrapper.unmount();
});
