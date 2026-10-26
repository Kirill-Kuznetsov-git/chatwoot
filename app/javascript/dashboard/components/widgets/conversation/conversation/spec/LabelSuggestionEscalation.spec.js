import { reactive } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import LabelSuggestion from '../LabelSuggestion.vue';

vi.mock('dashboard/composables/useConversationLabels');
vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: { value: true } }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => text }),
}));
vi.mock('dashboard/composables', () => ({ useTrack: vi.fn() }));

it('saves suggested taxonomy before proposing Escalated and never sets that tag directly', async () => {
  const addLabelToConversation = vi.fn();
  useConversationLabels.mockReturnValue({ addLabelToConversation });
  const store = {
    dispatch: vi.fn(),
    getters: {
      'labels/getLabels': ['psp', 'deposit', 'escalated'].map(title => ({
        title,
      })),
      getCurrentAccountId: 1,
      getSelectedChat: {
        id: 1,
        manual_escalation_details: {
          enabled: true,
          escalation_label: 'escalated',
        },
      },
    },
  };
  store.getters = reactive(store.getters);
  const wrapper = shallowMount(LabelSuggestion, {
    props: { suggestedLabels: ['psp', 'deposit', 'escalated'] },
    global: {
      mocks: { $store: store, $t: key => key },
      stubs: { WootLabel: true },
    },
  });
  await wrapper.vm.addAllLabels();
  expect(store.dispatch).toHaveBeenCalledWith('conversationLabels/update', {
    conversationId: 1,
    labels: ['psp', 'deposit'],
  });
  expect(addLabelToConversation).toHaveBeenCalledWith({ title: 'escalated' });
  expect(store.dispatch.mock.invocationCallOrder[0]).toBeLessThan(
    addLabelToConversation.mock.invocationCallOrder[0]
  );
  wrapper.unmount();
});

it('does not propose an escalation in another conversation after saving suggested taxonomy', async () => {
  const addLabelToConversation = vi.fn();
  useConversationLabels.mockReturnValue({ addLabelToConversation });
  let complete;
  const store = {
    dispatch: vi.fn(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    ),
    getters: {
      'labels/getLabels': ['psp', 'escalated'].map(title => ({ title })),
      getCurrentAccountId: 1,
      getSelectedChat: {
        id: 1,
        manual_escalation_details: {
          enabled: true,
          escalation_label: 'escalated',
        },
      },
    },
  };
  store.getters = reactive(store.getters);
  const wrapper = shallowMount(LabelSuggestion, {
    props: { suggestedLabels: ['psp', 'escalated'] },
    global: {
      mocks: { $store: store, $t: key => key },
      stubs: { WootLabel: true },
    },
  });
  const applying = wrapper.vm.addAllLabels();
  store.getters.getSelectedChat = { id: 2 };
  complete();
  await applying;
  expect(addLabelToConversation).not.toHaveBeenCalled();
  wrapper.unmount();
});
