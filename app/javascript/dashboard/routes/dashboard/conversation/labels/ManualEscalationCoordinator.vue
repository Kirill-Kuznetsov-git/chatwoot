<script setup>
import { onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import ManualEscalationModal from './ManualEscalationModal.vue';

const { t } = useI18n();
const {
  escalationProposal,
  escalationBusy,
  escalationError,
  confirmEscalation,
  cancelEscalation,
} = useConversationLabels({ coordinate: true });

onUnmounted(cancelEscalation);
</script>

<template>
  <p
    v-if="escalationError && !escalationProposal"
    role="alert"
    class="fixed bottom-4 end-4 z-50 max-w-sm rounded-lg bg-n-solid-2 p-4 text-sm text-n-ruby-11 shadow-lg"
  >
    {{ t('CONVERSATION.MANUAL_ESCALATION.ERROR') }}
  </p>
  <ManualEscalationModal
    v-if="escalationProposal"
    :key="escalationProposal.conversationId"
    :details="escalationProposal"
    :busy="escalationBusy"
    :error="escalationError"
    @confirm="confirmEscalation"
    @cancel="cancelEscalation"
  />
</template>
