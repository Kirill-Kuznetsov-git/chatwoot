import { getAllConversationsAPI } from 'widget/api/conversation';
import {
  L1_LABEL_PREFIX,
  hasLabelWithPrefix,
} from 'widget/constants/levels';

const state = {
  records: [],
  uiFlags: {
    isFetching: false,
  },
};

const isUnread = conv => {
  const lastMsg = conv && conv.last_message;
  if (!lastMsg) return false;
  // message_type: 0 = incoming (from contact), 1 = outgoing (from agent/bot)
  if (lastMsg.message_type !== 1) return false;
  return (lastMsg.created_at || 0) > (conv.contact_last_seen_at || 0);
};

const getters = {
  getAll: $state => $state.records,
  isFetching: $state => $state.uiFlags.isFetching,
  hasL1Conversation: $state =>
    $state.records.some(
      conv =>
        ['open', 'pending'].includes(conv.status) &&
        hasLabelWithPrefix(conv.labels, L1_LABEL_PREFIX)
    ),
  isConversationUnread: $state => conversationId =>
    isUnread($state.records.find(r => r.id === conversationId)),
  totalUnreadCount: $state => $state.records.filter(isUnread).length,
};

const actions = {
  async fetchAll({ commit }) {
    commit('setFetching', true);
    try {
      const { data } = await getAllConversationsAPI();
      commit('setRecords', Array.isArray(data) ? data : []);
    } catch (error) {
      commit('setRecords', []);
    } finally {
      commit('setFetching', false);
    }
  },
  // Patch the matching record with a freshly received message (from
  // ActionCable). If the record doesn't exist yet — e.g. a brand new
  // conversation was just created — fall back to a full refetch.
  applyIncomingMessage({ commit, state, dispatch }, message) {
    if (!message || !message.conversation_id) return;
    const conv = state.records.find(r => r.id === message.conversation_id);
    if (!conv) {
      dispatch('fetchAll');
      return;
    }
    commit('patchRecord', {
      id: conv.id,
      changes: {
        last_message: {
          id: message.id,
          content: message.content,
          message_type: message.message_type,
          created_at: message.created_at,
        },
        last_activity_at: message.created_at || conv.last_activity_at,
      },
    });
  },
  markRead({ commit }, conversationId) {
    commit('patchRecord', {
      id: conversationId,
      changes: { contact_last_seen_at: Math.floor(Date.now() / 1000) },
    });
  },
};

const mutations = {
  setRecords($state, records) {
    $state.records = records;
  },
  setFetching($state, value) {
    $state.uiFlags.isFetching = value;
  },
  patchRecord($state, { id, changes }) {
    $state.records = $state.records.map(r =>
      r.id === id ? { ...r, ...changes } : r
    );
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
