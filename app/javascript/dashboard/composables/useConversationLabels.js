import { computed, ref, watch } from 'vue';
import ConversationAPI from 'dashboard/api/conversations';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

// Each dashboard store owns one flow, shared by sidebar and command-bar callers.
const escalationStates = new WeakMap();

/**
 * Composable for managing conversation labels
 * @returns {Object} An object containing methods and computed properties for conversation labels
 */
export function useConversationLabels({ coordinate = false } = {}) {
  const store = useStore();
  const getters = useStoreGetters();

  /**
   * The currently selected chat
   * @type {import('vue').ComputedRef<Object>}
   */
  const currentChat = computed(() => getters.getSelectedChat.value);

  /**
   * The ID of the current conversation
   * @type {import('vue').ComputedRef<number|null>}
   */
  const conversationId = computed(() => currentChat.value?.id);
  const accountId = computed(
    () => getters.getCurrentAccountId?.value ?? currentChat.value?.account_id
  );

  /**
   * All labels available for the account
   * @type {import('vue').ComputedRef<Array>}
   */
  const accountLabels = computed(() => getters['labels/getLabels'].value);

  /**
   * Labels currently saved to the conversation
   * @type {import('vue').ComputedRef<Array>}
   */
  const savedLabels = computed(() => {
    return store.getters['conversationLabels/getConversationLabels'](
      conversationId.value
    );
  });

  /**
   * Labels currently active on the conversation
   * @type {import('vue').ComputedRef<Array>}
   */
  const activeLabels = computed(() =>
    accountLabels.value.filter(({ title }) => savedLabels.value.includes(title))
  );

  /**
   * Labels available but not active on the conversation
   * @type {import('vue').ComputedRef<Array>}
   */
  const inactiveLabels = computed(() =>
    accountLabels.value.filter(
      ({ title }) => !savedLabels.value.includes(title)
    )
  );

  /**
   * Updates the labels for the current conversation
   * @param {string[]} selectedLabels - Array of label titles to be set for the conversation
   * @returns {Promise<void>}
   */
  const onUpdateLabels = async selectedLabels => {
    await store.dispatch('conversationLabels/update', {
      conversationId: conversationId.value,
      labels: selectedLabels,
    });
  };

  /**
   * Adds a label to the current conversation
   * @param {Object} value - The label object to be added
   * @param {string} value.title - The title of the label to be added
   */
  if (!escalationStates.has(store)) {
    escalationStates.set(store, {
      escalationProposal: ref(null),
      escalationError: ref(false),
      escalationBusy: ref(false),
      requestVersion: 0,
    });
  }
  const escalationState = escalationStates.get(store);
  const { escalationProposal, escalationError, escalationBusy } =
    escalationState;

  const cancelEscalation = () => {
    escalationState.requestVersion += 1;
    escalationProposal.value = null;
    escalationError.value = false;
  };
  // Only the always-mounted dashboard coordinator owns navigation cleanup.
  if (coordinate) {
    // List sorting can briefly remove a chat from the selected-record lookup.
    // Only a change to the stored selection is actual conversation navigation.
    watch([getters.getSelectedChatId, accountId], cancelEscalation, {
      flush: 'sync',
    });
  }

  const confirmEscalation = async values => {
    const proposal = escalationProposal.value;
    if (
      !proposal ||
      proposal.conversationId !== conversationId.value ||
      escalationBusy.value
    )
      return;
    const version = escalationState.requestVersion;
    escalationBusy.value = true;
    escalationError.value = false;
    try {
      const { data } = await ConversationAPI.updateManualEscalationDetails(
        proposal.conversationId,
        { ...values, escalate: true }
      );
      if (version !== escalationState.requestVersion) return;
      await store.dispatch('conversationLabels/setConversationLabel', {
        id: proposal.conversationId,
        data: data.labels,
      });
      if (proposal === escalationProposal.value) cancelEscalation();
    } catch {
      if (proposal === escalationProposal.value) escalationError.value = true;
    } finally {
      escalationBusy.value = false;
    }
  };

  const addLabelToConversation = async value => {
    const config = currentChat.value?.manual_escalation_details;
    if (
      config?.enabled &&
      value.title.toLowerCase() === config.escalation_label
    ) {
      if (escalationBusy.value) return;
      const id = conversationId.value;
      escalationState.requestVersion += 1;
      const version = escalationState.requestVersion;
      escalationBusy.value = true;
      escalationError.value = false;
      try {
        const { data } = await ConversationAPI.getManualEscalationDetails(id);
        if (
          version !== escalationState.requestVersion ||
          id !== conversationId.value
        )
          return;
        if (data.enabled)
          escalationProposal.value = { ...data, conversationId: id };
        else await onUpdateLabels([...savedLabels.value, value.title]);
      } catch {
        if (
          version === escalationState.requestVersion &&
          id === conversationId.value
        )
          escalationError.value = true;
      } finally {
        escalationBusy.value = false;
      }
      return;
    }
    const result = activeLabels.value.map(item => item.title);
    result.push(value.title);
    onUpdateLabels(result);
  };

  /**
   * Removes a label from the current conversation
   * @param {string} value - The title of the label to be removed
   */
  const removeLabelFromConversation = value => {
    const result = activeLabels.value
      .map(label => label.title)
      .filter(label => label !== value);
    onUpdateLabels(result);
  };

  return {
    escalationProposal,
    escalationError,
    escalationBusy,
    cancelEscalation,
    confirmEscalation,
    accountLabels,
    savedLabels,
    activeLabels,
    inactiveLabels,
    addLabelToConversation,
    removeLabelFromConversation,
    onUpdateLabels,
  };
}
