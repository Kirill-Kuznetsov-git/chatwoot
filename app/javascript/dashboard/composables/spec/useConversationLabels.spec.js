import { useConversationLabels } from '../useConversationLabels';
import { computed, nextTick, reactive } from 'vue';
import ConversationAPI from 'dashboard/api/conversations';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/api/conversations', () => ({
  default: {
    getManualEscalationDetails: vi.fn(),
    updateManualEscalationDetails: vi.fn(),
  },
}));

describe('useConversationLabels', () => {
  let store;
  let getters;

  beforeEach(() => {
    store = {
      getters: {
        'conversationLabels/getConversationLabels': vi.fn(),
      },
      dispatch: vi.fn(),
    };
    getters = {
      getSelectedChat: { value: { id: 1 } },
      'labels/getLabels': {
        value: [
          { id: 1, title: 'Label 1' },
          { id: 2, title: 'Label 2' },
          { id: 3, title: 'Label 3' },
        ],
      },
    };
    getters.getSelectedChatId = computed(
      () => getters.getSelectedChat.value.id
    );

    useStore.mockReturnValue(store);
    useStoreGetters.mockReturnValue(getters);
  });

  it('should return the correct computed properties', () => {
    store.getters['conversationLabels/getConversationLabels'].mockReturnValue([
      'Label 1',
      'Label 2',
    ]);
    const { accountLabels, savedLabels, activeLabels, inactiveLabels } =
      useConversationLabels();

    expect(accountLabels.value).toEqual(getters['labels/getLabels'].value);
    expect(savedLabels.value).toEqual(['Label 1', 'Label 2']);
    expect(activeLabels.value).toEqual([
      { id: 1, title: 'Label 1' },
      { id: 2, title: 'Label 2' },
    ]);
    expect(inactiveLabels.value).toEqual([{ id: 3, title: 'Label 3' }]);
  });

  it('should update labels correctly', async () => {
    const { onUpdateLabels } = useConversationLabels();
    await onUpdateLabels(['Label 1', 'Label 3']);

    expect(store.dispatch).toHaveBeenCalledWith('conversationLabels/update', {
      conversationId: 1,
      labels: ['Label 1', 'Label 3'],
    });
  });

  it('should add a label to the conversation', () => {
    store.getters['conversationLabels/getConversationLabels'].mockReturnValue([
      'Label 1',
    ]);
    const { addLabelToConversation } = useConversationLabels();

    addLabelToConversation({ title: 'Label 2' });

    expect(store.dispatch).toHaveBeenCalledWith('conversationLabels/update', {
      conversationId: 1,
      labels: ['Label 1', 'Label 2'],
    });
  });

  it('should remove a label from the conversation', () => {
    store.getters['conversationLabels/getConversationLabels'].mockReturnValue([
      'Label 1',
      'Label 2',
    ]);
    const { removeLabelFromConversation } = useConversationLabels();

    removeLabelFromConversation('Label 2');

    expect(store.dispatch).toHaveBeenCalledWith('conversationLabels/update', {
      conversationId: 1,
      labels: ['Label 1'],
    });
  });
  describe('manual escalation confirmation', () => {
    beforeEach(() => {
      getters.getSelectedChat = reactive({
        value: {
          id: 1,
          manual_escalation_details: {
            enabled: true,
            escalation_label: 'escalated',
          },
        },
      });
      store.getters['conversationLabels/getConversationLabels'].mockReturnValue(
        ['Label 1']
      );
      ConversationAPI.getManualEscalationDetails.mockResolvedValue({
        data: {
          enabled: true,
          title: 'Automatic',
          title_override: '',
          reason: '',
          reasons: ['Other'],
          max_length: 150,
        },
      });
    });

    it('shares proposals between separate callers in the same store but isolates other stores', async () => {
      const source = useConversationLabels();
      const host = useConversationLabels();
      await source.addLabelToConversation({ title: 'escalated' });
      expect(host.escalationProposal.value?.title).toBe('Automatic');
      useStore.mockReturnValue({ ...store });
      const otherStore = useConversationLabels();
      expect(otherStore.escalationProposal.value).toBeNull();
      host.cancelEscalation();
      expect(source.escalationProposal.value).toBeNull();
    });

    it('cancels on account-route changes even while the previous selected chat remains cached', async () => {
      getters.getCurrentAccountId = reactive({ value: 1 });
      const labels = useConversationLabels({ coordinate: true });
      await labels.addLabelToConversation({ title: 'escalated' });
      getters.getCurrentAccountId.value = 2;
      await nextTick();
      expect(labels.escalationProposal.value).toBeNull();
    });

    it('opens a proposal without posting the escalation label and cancel does not write', async () => {
      const labels = useConversationLabels({ coordinate: true });
      await labels.addLabelToConversation({ title: 'escalated' });
      expect(labels.escalationProposal.value.title).toBe('Automatic');
      expect(store.dispatch).not.toHaveBeenCalled();
      labels.cancelEscalation();
      expect(labels.escalationProposal.value).toBeNull();
      expect(
        ConversationAPI.updateManualEscalationDetails
      ).not.toHaveBeenCalled();
    });

    it('confirms once with the explicit override, then refreshes labels', async () => {
      ConversationAPI.updateManualEscalationDetails.mockResolvedValue({
        data: { labels: ['Label 1', 'escalated'] },
      });
      const labels = useConversationLabels({ coordinate: true });
      await labels.addLabelToConversation({ title: 'escalated' });
      await labels.confirmEscalation({ title: '', reason: 'Other' });
      expect(
        ConversationAPI.updateManualEscalationDetails
      ).toHaveBeenCalledWith(1, { title: '', reason: 'Other', escalate: true });
      expect(store.dispatch).toHaveBeenCalledWith(
        'conversationLabels/setConversationLabel',
        { id: 1, data: ['Label 1', 'escalated'] }
      );
      expect(labels.escalationProposal.value).toBeNull();
    });

    it('keeps the form open on save failure and never posts labels as a fallback', async () => {
      ConversationAPI.updateManualEscalationDetails.mockRejectedValue(
        new Error('offline')
      );
      const labels = useConversationLabels({ coordinate: true });
      await labels.addLabelToConversation({ title: 'escalated' });
      await labels.confirmEscalation({ title: 'Manual', reason: '' });
      expect(labels.escalationProposal.value).not.toBeNull();
      expect(labels.escalationError.value).toBe(true);
      expect(store.dispatch).not.toHaveBeenCalled();
    });

    it('does not escalate on an unknown endpoint or late navigation response', async () => {
      const labels = useConversationLabels({ coordinate: true });
      ConversationAPI.getManualEscalationDetails.mockRejectedValueOnce(
        new Error('404')
      );
      await labels.addLabelToConversation({ title: 'escalated' });
      expect(store.dispatch).not.toHaveBeenCalled();
      let complete;
      ConversationAPI.getManualEscalationDetails.mockReturnValue(
        new Promise(resolve => {
          complete = resolve;
        })
      );
      const pending = labels.addLabelToConversation({ title: 'escalated' });
      getters.getSelectedChat.value = { id: 2 };
      await nextTick();
      complete({ data: { enabled: true, title: 'Old' } });
      await pending;
      expect(labels.escalationProposal.value).toBeNull();
      expect(store.dispatch).not.toHaveBeenCalled();
    });

    it('does not apply an old save response after navigation to the same id in another account', async () => {
      getters.getSelectedChat.value.account_id = 1;
      const labels = useConversationLabels({ coordinate: true });
      await labels.addLabelToConversation({ title: 'escalated' });
      let complete;
      ConversationAPI.updateManualEscalationDetails.mockReturnValue(
        new Promise(resolve => {
          complete = resolve;
        })
      );
      const saving = labels.confirmEscalation({ title: '', reason: '' });
      getters.getSelectedChat.value = { id: 1, account_id: 2 };
      await nextTick();
      expect(labels.escalationProposal.value).toBeNull();
      complete({ data: { labels: ['escalated'] } });
      await saving;
      expect(store.dispatch).not.toHaveBeenCalled();
    });

    it('cancels a proposal on navigation and cannot save it into another conversation', async () => {
      const labels = useConversationLabels({ coordinate: true });
      await labels.addLabelToConversation({ title: 'escalated' });
      getters.getSelectedChat.value = { id: 2 };
      await nextTick();
      await labels.confirmEscalation({ title: 'Manual', reason: '' });
      expect(labels.escalationProposal.value).toBeNull();
      expect(
        ConversationAPI.updateManualEscalationDetails
      ).not.toHaveBeenCalled();
    });
  });
});
