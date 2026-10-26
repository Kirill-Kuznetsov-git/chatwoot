import { computed, reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import {
  useStore,
  useStoreGetters,
  useMapGetter,
} from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import { useConversationHotKeys } from 'dashboard/composables/commands/useConversationHotKeys';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import ConversationAPI from 'dashboard/api/conversations';
import ManualEscalationCoordinator from '../ManualEscalationCoordinator.vue';

vi.mock('dashboard/composables/store');
vi.mock('vue-router');
vi.mock('vue-i18n', async importOriginal => ({
  ...(await importOriginal()),
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/composables/useCaptain');
vi.mock('dashboard/composables/useAgentsList');
vi.mock('dashboard/api/conversations', () => ({
  default: {
    getManualEscalationDetails: vi.fn(),
    updateManualEscalationDetails: vi.fn(),
  },
}));

let store;
let wrapper;
let command;
const details = {
  enabled: true,
  title: 'Automatic topic',
  title_override: '',
  reason: '',
  reasons: ['Other'],
  max_length: 150,
};

beforeEach(() => {
  store = {
    dispatch: vi.fn(),
    getters: reactive({
      getSelectedChat: {
        id: 1,
        account_id: 1,
        status: 'open',
        manual_escalation_details: {
          enabled: true,
          escalation_label: 'escalated',
        },
      },
      'labels/getLabels': [{ id: 1, title: 'escalated' }],
      'conversationLabels/getConversationLabels': () => [],
      'draftMessages/getReplyEditorMode': 'reply',
      getContextMenuChatId: null,
      'teams/getTeams': [],
      'draftMessages/get': () => '',
    }),
  };
  useStore.mockReturnValue(store);
  useStoreGetters.mockImplementation(() =>
    Object.fromEntries(
      Object.keys(store.getters).map(key => [
        key,
        computed(() => store.getters[key]),
      ])
    )
  );
  useMapGetter.mockImplementation(key => computed(() => store.getters[key]));
  useRoute.mockReturnValue({ name: 'inbox_conversation' });
  useCaptain.mockReturnValue({ captainTasksEnabled: { value: false } });
  useAgentsList.mockReturnValue({
    agentsList: { value: [] },
    assignableAgents: { value: [] },
  });
  ConversationAPI.getManualEscalationDetails.mockResolvedValue({
    data: details,
  });
  ConversationAPI.updateManualEscalationDetails.mockResolvedValue({
    data: { labels: ['escalated'] },
  });
  // Only the root coordinator is mounted: the conversation sidebar/LabelBox is absent.
  wrapper = mount(ManualEscalationCoordinator, {
    global: {
      stubs: {
        Dialog: {
          template:
            '<div><slot /><button data-confirm @click="$emit(\'confirm\')">Confirm</button><button data-cancel @click="$emit(\'close\')">Cancel</button></div>',
          methods: { open() {} },
        },
      },
    },
  });
  const { conversationHotKeys } = useConversationHotKeys();
  command = conversationHotKeys.value.find(action => action.id === 'escalated');
});
afterEach(() => wrapper.unmount());

describe('dashboard escalation coordinator without conversation sidebar', () => {
  it('shows a modal from the real command action, does not post early, and cancel discards the proposal', async () => {
    await command.handler(command);
    await flushPromises();
    expect(wrapper.find('input').element.value).toBe('Automatic topic');
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(
      ConversationAPI.updateManualEscalationDetails
    ).not.toHaveBeenCalled();
    await wrapper.find('[data-cancel]').trigger('click');
    expect(wrapper.find('input').exists()).toBe(false);
    expect(
      ConversationAPI.updateManualEscalationDetails
    ).not.toHaveBeenCalled();
  });

  it('confirms a command-bar escalation through the atomic details endpoint', async () => {
    await command.handler(command);
    await flushPromises();
    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();
    expect(ConversationAPI.updateManualEscalationDetails).toHaveBeenCalledWith(
      1,
      { title: '', reason: '', escalate: true }
    );
    expect(store.dispatch).toHaveBeenCalledWith(
      'conversationLabels/setConversationLabel',
      { id: 1, data: ['escalated'] }
    );
    expect(wrapper.find('input').exists()).toBe(false);
  });

  it('keeps a failed save visible and closes the proposal on account navigation', async () => {
    await command.handler(command);
    await flushPromises();
    ConversationAPI.updateManualEscalationDetails.mockRejectedValue(
      new Error('offline')
    );
    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(store.dispatch).not.toHaveBeenCalled();
    store.getters.getSelectedChat = { id: 1, account_id: 2 };
    await flushPromises();
    expect(wrapper.find('input').exists()).toBe(false);
  });

  it('keeps a proposal when an unrelated label caller is unmounted', async () => {
    await command.handler(command);
    await flushPromises();
    const caller = mount({
      setup() {
        useConversationLabels();
        return () => null;
      },
    });
    caller.unmount();
    expect(wrapper.find('input').exists()).toBe(true);
  });
});
