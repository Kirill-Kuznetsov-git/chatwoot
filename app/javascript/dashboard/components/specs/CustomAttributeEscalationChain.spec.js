import { computed, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import actions from 'dashboard/store/modules/conversations/actions';
import CustomAttributes from 'dashboard/routes/dashboard/conversation/customAttributes/CustomAttributes.vue';
import CustomAttribute from '../CustomAttribute.vue';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useUISettings');
vi.mock('vue-router');
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

let commit;
let store;
let wrapper;

beforeEach(() => {
  commit = vi.fn();
  global.axios = { post: vi.fn() };
  store = {
    getters: reactive({
      getSelectedChat: {
        id: 1,
        custom_attributes: {
          manual_escalation_title: 'Manual',
          manual_escalation_reason: 'Другое',
          legacy_field: 'Unchanged',
        },
      },
      'attributes/getAttributesByModel': () =>
        [
          'manual_escalation_title',
          'manual_escalation_reason',
          'legacy_field',
        ].map((key, index) => ({
          id: index + 1,
          attribute_key: key,
          attribute_display_name: key,
          attribute_display_type: 'text',
        })),
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
  wrapper = mount(CustomAttributes, {
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
});
afterEach(() => wrapper.unmount());

it('sends an empty native title from the actual input through the sidebar and Vuex action to HTTP', async () => {
  const attributes = {
    ...store.getters.getSelectedChat.custom_attributes,
    manual_escalation_title: '',
  };
  global.axios.post.mockResolvedValue({
    data: { custom_attributes: attributes },
  });
  const title = wrapper.findAllComponents(CustomAttribute)[0];
  await title.vm.onEdit();
  await title.find('input').setValue('');
  await title.find('input').trigger('keyup.enter');
  await flushPromises();
  expect(global.axios.post).toHaveBeenCalledWith(
    expect.stringContaining('/1/custom_attributes'),
    { custom_attributes: attributes }
  );
  expect(commit).toHaveBeenCalledWith(expect.any(String), {
    conversationId: 1,
    customAttributes: attributes,
  });
  expect(useAlert).toHaveBeenCalledWith(
    wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.UPDATE.SUCCESS')
  );
});

it('shows the title limit error for HTTP422 without a success notice or state update', async () => {
  global.axios.post.mockRejectedValue({
    response: { status: 422, data: { message: 'Invalid custom attributes' } },
  });
  const title = wrapper.findAllComponents(CustomAttribute)[0];
  await title.vm.onEdit();
  await title.find('input').setValue('x'.repeat(151));
  await title.find('input').trigger('keyup.enter');
  await flushPromises();
  expect(global.axios.post).toHaveBeenCalled();
  expect(commit).not.toHaveBeenCalled();
  expect(
    store.getters.getSelectedChat.custom_attributes.manual_escalation_title
  ).toBe('Manual');
  expect(useAlert).toHaveBeenCalledWith(
    wrapper.vm.$t('CONVERSATION.MANUAL_ESCALATION.INVALID')
  );
  expect(useAlert).not.toHaveBeenCalledWith(
    wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.UPDATE.SUCCESS')
  );
});

it.each(['manual_escalation_title', 'manual_escalation_reason'])(
  'reports a network error when updating %s',
  async key => {
    global.axios.post.mockRejectedValue(new Error('offline'));
    const field = wrapper
      .findAllComponents(CustomAttribute)
      .find(component => component.props('attributeKey') === key);
    field.vm.$emit('update', key, 'New value');
    await flushPromises();
    expect(global.axios.post).toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.UPDATE.ERROR')
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.UPDATE.SUCCESS')
    );
  }
);

it.each(['manual_escalation_title', 'manual_escalation_reason'])(
  'reports a failed delete of %s without changing state',
  async key => {
    global.axios.post.mockRejectedValue({ response: { status: 422 } });
    const before = { ...store.getters.getSelectedChat.custom_attributes };
    const field = wrapper
      .findAllComponents(CustomAttribute)
      .find(component => component.props('attributeKey') === key);
    field.vm.onDelete();
    await flushPromises();
    expect(global.axios.post).toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
    expect(store.getters.getSelectedChat.custom_attributes).toEqual(before);
    expect(useAlert).toHaveBeenCalledWith(
      wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.DELETE.ERROR')
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.DELETE.SUCCESS')
    );
  }
);

it.each(['UPDATE', 'DELETE'])(
  'keeps the existing %s error contract for unrelated native attributes',
  async operation => {
    global.axios.post.mockRejectedValue(new Error('offline'));
    const field = wrapper.findAllComponents(CustomAttribute)[2];
    if (operation === 'UPDATE')
      field.vm.$emit('update', 'legacy_field', 'New value');
    else field.vm.onDelete();
    await flushPromises();
    expect(commit).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      operation === 'UPDATE'
        ? wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.UPDATE.SUCCESS')
        : wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.DELETE.SUCCESS')
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      operation === 'UPDATE'
        ? wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.UPDATE.ERROR')
        : wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.DELETE.ERROR')
    );
  }
);

it('shows the ordinary update error for an invalid reason rather than a title-limit error', async () => {
  global.axios.post.mockRejectedValue({ response: { status: 422 } });
  const field = wrapper.findAllComponents(CustomAttribute)[1];
  field.vm.$emit('update', 'manual_escalation_reason', 'Invalid reason');
  await flushPromises();
  expect(commit).not.toHaveBeenCalled();
  expect(useAlert).toHaveBeenCalledWith(
    wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.UPDATE.ERROR')
  );
  expect(useAlert).not.toHaveBeenCalledWith(
    wrapper.vm.$t('CUSTOM_ATTRIBUTES.FORM.UPDATE.SUCCESS')
  );
  expect(useAlert).not.toHaveBeenCalledWith(
    wrapper.vm.$t('CONVERSATION.MANUAL_ESCALATION.INVALID')
  );
});
