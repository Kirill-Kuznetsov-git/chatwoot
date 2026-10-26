<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  details: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
});
const emit = defineEmits(['confirm', 'cancel']);
const { t } = useI18n();
const dialog = ref(null);
const title = ref(props.details.title);
const reason = ref(props.details.reason);
const length = computed(() => Array.from(title.value.trim()).length);
const valid = computed(
  () =>
    length.value <= props.details.max_length &&
    !/[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/u.test(
      title.value.replace(/\u200D/gu, '')
    )
);
const confirm = () => {
  if (!valid.value || props.busy) return;
  emit('confirm', {
    title:
      title.value === props.details.title
        ? props.details.title_override
        : title.value,
    reason: reason.value,
  });
};
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('CONVERSATION.MANUAL_ESCALATION.TITLE')"
    :description="t('CONVERSATION.MANUAL_ESCALATION.DESCRIPTION')"
    :confirm-button-label="t('CONVERSATION.MANUAL_ESCALATION.CONFIRM')"
    :disable-confirm-button="!valid"
    :is-loading="busy"
    @confirm="confirm"
    @close="emit('cancel')"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('CONVERSATION.MANUAL_ESCALATION.SLACK_TITLE') }}
        <input
          v-model="title"
          autofocus
          type="text"
          :placeholder="details.title"
          :aria-invalid="!valid"
        />
        <span class="text-xs text-n-slate-11">{{
          t('CONVERSATION.MANUAL_ESCALATION.COUNT', {
            count: length,
            max: details.max_length,
          })
        }}</span>
      </label>
      <p class="text-sm text-n-slate-11">
        {{ t('CONVERSATION.MANUAL_ESCALATION.AUTO_HINT') }}
      </p>
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('CONVERSATION.MANUAL_ESCALATION.REASON') }}
        <select v-model="reason">
          <option value="">
            {{ t('CONVERSATION.MANUAL_ESCALATION.NO_REASON') }}
          </option>
          <option
            v-for="option in details.reasons"
            :key="option"
            :value="option"
          >
            {{ option }}
          </option>
        </select>
      </label>
      <p v-if="!valid" role="alert" class="text-sm text-n-ruby-11">
        {{ t('CONVERSATION.MANUAL_ESCALATION.INVALID') }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ t('CONVERSATION.MANUAL_ESCALATION.ERROR') }}
      </p>
    </div>
  </Dialog>
</template>
