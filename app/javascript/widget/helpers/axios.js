import axios from 'axios';
import { APP_BASE_URL } from 'widget/helpers/constants';

export const API = axios.create({
  baseURL: APP_BASE_URL,
  withCredentials: false,
});

// Inject the currently-selected conversation_id from the Vuex store into
// every widget API request, so the backend can resolve a specific
// conversation instead of always falling back to `.last`.
//
// The store is imported lazily inside the interceptor to avoid creating a
// circular dependency (store imports modules → modules import API).
let getActiveConversationId = () => null;
export const registerActiveConversationGetter = fn => {
  getActiveConversationId = fn;
};

API.interceptors.request.use(config => {
  const activeId = getActiveConversationId();
  if (!activeId) return config;

  const params = { ...(config.params || {}) };
  if (!params.conversation_id) {
    params.conversation_id = activeId;
  }
  return { ...config, params };
});

export const setHeader = (value, key = 'X-Auth-Token') => {
  API.defaults.headers.common[key] = value;
};

export const removeHeader = key => {
  delete API.defaults.headers.common[key];
};
