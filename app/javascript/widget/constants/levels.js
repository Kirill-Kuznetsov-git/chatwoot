// Label prefixes that classify conversations into support tiers.
// Examples: l1, l1_withdrawals, l1_payments, l2, l2_withdrawals.
// Code only checks the prefix — actual label names are managed in Chatwoot UI.
export const L1_LABEL_PREFIX = 'l1';
export const L2_LABEL_PREFIX = 'l2';

export const hasLabelWithPrefix = (labels = [], prefix) =>
  Array.isArray(labels) && labels.some(label => label && label.startsWith(prefix));
