import { computed } from 'vue';
import { createStore } from 'vuex';
import ActionCableConnector from '../actionCable';
import conversationModule from 'dashboard/store/modules/conversations';
import contacts from 'dashboard/store/modules/contacts';
import { matchesFilters } from 'dashboard/store/modules/conversations/helpers/filterHelpers';

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: { create: () => ({ perform: () => {} }) },
  }),
}));
vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({ isImpersonating: { value: false } }),
}));

describe('contact.updated segment filters', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('refreshes every loaded conversation of that contact, including removal, without changing selection or other contacts', async () => {
    const store = createStore({
      ...conversationModule,
      state: () => ({
        allConversations: [
          {
            id: 1,
            care_segment: { weight: 'Small Fish' },
            meta: { sender: { id: 7, name: 'Keep name' } },
          },
          { id: 2, meta: { sender: { id: 7 } } },
          { id: 3, meta: { sender: { id: 8 } } },
        ],
        selectedChatId: 1,
      }),
      getters: { getCurrentAccountId: () => 1, getCurrentUserID: () => 529 },
      modules: { contacts },
    });
    const filters = [
      {
        attribute_key: 'care_segment_weight',
        filter_operator: 'equal_to',
        values: ['Whale'],
      },
    ];
    const matchingIds = computed(() =>
      store.state.allConversations
        .filter(c => matchesFilters(c, filters))
        .map(c => c.id)
    );
    const connector = ActionCableConnector.init(store, 'synthetic');
    expect(matchingIds.value).toEqual([]);
    await connector.onContactUpdate({
      id: 7,
      custom_attributes: { segment_weight: 'Whale', segment_role: 'Seller' },
    });
    expect(matchingIds.value).toEqual([1, 2]);
    expect(store.state.allConversations[0].meta.sender.name).toBe('Keep name');
    expect(store.state.selectedChatId).toBe(1);
    await connector.onContactUpdate({ id: 7, name: 'Partial unrelated event' });
    expect(matchingIds.value).toEqual([1, 2]);
    await connector.onContactUpdate({ id: 7, custom_attributes: {} });
    expect(matchingIds.value).toEqual([]);
  });
});
