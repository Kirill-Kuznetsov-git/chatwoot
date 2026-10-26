/* global axios */
import ApiClient from './ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getLabels(conversationID) {
    return axios.get(`${this.url}/${conversationID}/labels`);
  }

  updateLabels(conversationID, labels) {
    return axios.post(`${this.url}/${conversationID}/labels`, { labels });
  }

  getManualEscalationDetails(conversationId) {
    return axios.get(`${this.url}/${conversationId}/manual_escalation_details`);
  }

  updateManualEscalationDetails(conversationId, details) {
    return axios.post(
      `${this.url}/${conversationId}/manual_escalation_details`,
      details
    );
  }

  getUnreadCounts() {
    return axios.get(`${this.url}/unread_counts`);
  }
}

export default new ConversationApi();
