<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { useStoreGetters, useMapGetter } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import BroadcastCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/BroadcastCampaign/BroadcastCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import BroadcastCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/BroadcastCampaignEmptyState.vue';

const { t } = useI18n();
const getters = useStoreGetters();

const selectedCampaign = ref(null);
const [showBroadcastCampaignDialog, toggleBroadcastCampaignDialog] =
  useToggle();

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);

const confirmDeleteCampaignDialogRef = ref(null);

const broadcastCampaigns = computed(
  () => getters['campaigns/getBroadcastCampaigns'].value
);

const hasNoBroadcastCampaigns = computed(
  () => broadcastCampaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.BROADCAST.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.BROADCAST.NEW_CAMPAIGN')"
    @click="toggleBroadcastCampaignDialog()"
    @close="toggleBroadcastCampaignDialog(false)"
  >
    <template #action>
      <BroadcastCampaignDialog
        v-if="showBroadcastCampaignDialog"
        @close="toggleBroadcastCampaignDialog(false)"
      />
    </template>
    <div
      v-if="isFetchingCampaigns"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>
    <CampaignList
      v-else-if="!hasNoBroadcastCampaigns"
      :campaigns="broadcastCampaigns"
      is-broadcast-type
      @delete="handleDelete"
    />
    <BroadcastCampaignEmptyState
      v-else
      :title="t('CAMPAIGN.BROADCAST.EMPTY_STATE.TITLE')"
      :subtitle="t('CAMPAIGN.BROADCAST.EMPTY_STATE.SUBTITLE')"
      class="pt-14"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
  </CampaignLayout>
</template>
