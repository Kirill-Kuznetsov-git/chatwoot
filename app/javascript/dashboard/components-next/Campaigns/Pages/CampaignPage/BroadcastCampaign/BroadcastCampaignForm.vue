<script setup>
import { reactive, computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign';

import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();
const store = useStore();

const uiFlags = useMapGetter('campaigns/getUIFlags');
const inboxes = useMapGetter('inboxes/getWebsiteInboxes');
// Сегмент рассылки — сохранённый сегмент контактов (фильтр из раздела «Контакты»):
// условия по Care-атрибутам segment_role / segment_weight / segment_tier_90d строятся там,
// а аудитория пересчитывается в момент отправки.
const segments = useMapGetter('customViews/getContactCustomViews');

const senderList = ref([]);

const initialState = {
  title: '',
  message: '',
  inboxId: null,
  senderId: null,
  segmentId: null,
  scheduledAt: null,
};

const state = reactive({ ...initialState });

const rules = {
  title: { required, minLength: minLength(1) },
  message: { required, minLength: minLength(1) },
  inboxId: { required },
  senderId: { required },
  segmentId: { required },
  scheduledAt: { required },
};

const v$ = useVuelidate(rules, state);

const isCreating = computed(() => uiFlags.value.isCreating);

const currentDateTime = computed(() => {
  const now = new Date();
  const localTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return localTime.toISOString().slice(0, 16);
});

const mapToOptions = (items, valueKey, labelKey) =>
  items?.map(item => ({
    value: item[valueKey],
    label: item[labelKey],
  })) ?? [];

const inboxOptions = computed(() => mapToOptions(inboxes.value, 'id', 'name'));
const segmentOptions = computed(() =>
  mapToOptions(segments.value, 'id', 'name')
);
const senderOptions = computed(() =>
  mapToOptions(senderList.value, 'id', 'name')
);

const getErrorMessage = (field, errorKey) => {
  const baseKey = 'CAMPAIGN.BROADCAST.CREATE.FORM';
  return v$.value[field].$error ? t(`${baseKey}.${errorKey}.ERROR`) : '';
};

const formErrors = computed(() => ({
  title: getErrorMessage('title', 'TITLE'),
  message: getErrorMessage('message', 'MESSAGE'),
  inbox: getErrorMessage('inboxId', 'INBOX'),
  sender: getErrorMessage('senderId', 'SENT_BY'),
  segment: getErrorMessage('segmentId', 'SEGMENT'),
  scheduledAt: getErrorMessage('scheduledAt', 'SCHEDULED_AT'),
}));

const isSubmitDisabled = computed(() => v$.value.$invalid);

const formatToUTCString = localDateTime =>
  localDateTime ? new Date(localDateTime).toISOString() : null;

const resetState = () => Object.assign(state, initialState);

const handleCancel = () => emit('cancel');

// Отправитель — участник выбранного инбокса: от его имени уходит письмо, и именно он не даёт
// агент-боту забрать рассылочный диалог (Conversation#handle_campaign_status).
const handleInboxChange = async inboxId => {
  state.senderId = null;
  if (!inboxId) {
    senderList.value = [];
    return;
  }

  try {
    const response = await store.dispatch('inboxMembers/get', { inboxId });
    senderList.value = response?.data?.payload ?? [];
  } catch (error) {
    senderList.value = [];
    useAlert(
      error?.response?.message ??
        t('CAMPAIGN.BROADCAST.CREATE.FORM.API.ERROR_MESSAGE')
    );
  }
};

const prepareCampaignDetails = () => ({
  title: state.title,
  message: state.message,
  inbox_id: state.inboxId,
  sender_id: state.senderId,
  campaign_type: CAMPAIGN_TYPES.ONE_OFF,
  scheduled_at: formatToUTCString(state.scheduledAt),
  audience: [{ id: state.segmentId, type: 'Segment' }],
});

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  emit('submit', prepareCampaignDetails());
  resetState();
  handleCancel();
};

onMounted(() => store.dispatch('customViews/get', 'contact'));
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <Input
      v-model="state.title"
      :label="t('CAMPAIGN.BROADCAST.CREATE.FORM.TITLE.LABEL')"
      :placeholder="t('CAMPAIGN.BROADCAST.CREATE.FORM.TITLE.PLACEHOLDER')"
      :message="formErrors.title"
      :message-type="formErrors.title ? 'error' : 'info'"
    />

    <TextArea
      v-model="state.message"
      :label="t('CAMPAIGN.BROADCAST.CREATE.FORM.MESSAGE.LABEL')"
      :placeholder="t('CAMPAIGN.BROADCAST.CREATE.FORM.MESSAGE.PLACEHOLDER')"
      show-character-count
      :message="formErrors.message"
      :message-type="formErrors.message ? 'error' : 'info'"
    />

    <div class="flex flex-col gap-1">
      <label for="inbox" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.BROADCAST.CREATE.FORM.INBOX.LABEL') }}
      </label>
      <ComboBox
        id="inbox"
        v-model="state.inboxId"
        :options="inboxOptions"
        :has-error="!!formErrors.inbox"
        :placeholder="t('CAMPAIGN.BROADCAST.CREATE.FORM.INBOX.PLACEHOLDER')"
        :message="formErrors.inbox"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
        @update:model-value="handleInboxChange"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="sender" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.BROADCAST.CREATE.FORM.SENT_BY.LABEL') }}
      </label>
      <ComboBox
        id="sender"
        v-model="state.senderId"
        :options="senderOptions"
        :has-error="!!formErrors.sender"
        :placeholder="t('CAMPAIGN.BROADCAST.CREATE.FORM.SENT_BY.PLACEHOLDER')"
        :message="formErrors.sender"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="segment" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.BROADCAST.CREATE.FORM.SEGMENT.LABEL') }}
      </label>
      <ComboBox
        id="segment"
        v-model="state.segmentId"
        :options="segmentOptions"
        :has-error="!!formErrors.segment"
        :placeholder="t('CAMPAIGN.BROADCAST.CREATE.FORM.SEGMENT.PLACEHOLDER')"
        :message="
          formErrors.segment || t('CAMPAIGN.BROADCAST.CREATE.FORM.SEGMENT.HINT')
        "
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <Input
      v-model="state.scheduledAt"
      :label="t('CAMPAIGN.BROADCAST.CREATE.FORM.SCHEDULED_AT.LABEL')"
      type="datetime-local"
      :min="currentDateTime"
      :placeholder="
        t('CAMPAIGN.BROADCAST.CREATE.FORM.SCHEDULED_AT.PLACEHOLDER')
      "
      :message="formErrors.scheduledAt"
      :message-type="formErrors.scheduledAt ? 'error' : 'info'"
    />

    <div class="flex items-center justify-between w-full gap-3">
      <Button
        variant="faded"
        color="slate"
        type="button"
        :label="t('CAMPAIGN.BROADCAST.CREATE.FORM.BUTTONS.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="handleCancel"
      />
      <Button
        :label="t('CAMPAIGN.BROADCAST.CREATE.FORM.BUTTONS.CREATE')"
        class="w-full"
        type="submit"
        :is-loading="isCreating"
        :disabled="isCreating || isSubmitDisabled"
      />
    </div>
  </form>
</template>
