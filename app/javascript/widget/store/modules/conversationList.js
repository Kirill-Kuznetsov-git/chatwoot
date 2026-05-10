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

const getters = {
  getAll: $state => $state.records,
  isFetching: $state => $state.uiFlags.isFetching,
  hasL1Conversation: $state =>
    $state.records.some(
      conv =>
        ['open', 'pending'].includes(conv.status) &&
        hasLabelWithPrefix(conv.labels, L1_LABEL_PREFIX)
    ),
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
};

const mutations = {
  setRecords($state, records) {
    $state.records = records;
  },
  setFetching($state, value) {
    $state.uiFlags.isFetching = value;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
