<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { messageStamp } from 'shared/helpers/timeHelper';

const props = defineProps({
  inboxName: {
    type: String,
    default: '',
  },
  inboxIcon: {
    type: String,
    default: '',
  },
  scheduledAt: {
    type: Number,
    default: 0,
  },
  audienceSegments: {
    type: Array,
    default: () => [],
  },
  stats: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

const segmentNames = computed(() =>
  props.audienceSegments.map(segment => segment.name).join(', ')
);

const sentCount = computed(() => props.stats?.sent ?? 0);
const repliedCount = computed(() => props.stats?.replied ?? 0);
</script>

<template>
  <span class="flex-shrink-0 text-sm text-n-slate-11 whitespace-nowrap">
    {{ t('CAMPAIGN.BROADCAST.CARD.CAMPAIGN_DETAILS.SEGMENT') }}
  </span>
  <span class="flex-shrink-0 max-w-40 text-sm font-medium truncate text-n-slate-12">
    {{ segmentNames }}
  </span>

  <div class="flex items-center gap-1.5 flex-shrink-0">
    <Icon :icon="inboxIcon" class="flex-shrink-0 text-n-slate-12 size-3" />
    <span class="text-sm font-medium text-n-slate-12">
      {{ inboxName }}
    </span>
  </div>

  <span class="flex-shrink-0 text-sm text-n-slate-11 whitespace-nowrap">
    {{ t('CAMPAIGN.BROADCAST.CARD.CAMPAIGN_DETAILS.ON') }}
  </span>
  <span class="flex-shrink-0 text-sm font-medium text-n-slate-12">
    {{ messageStamp(scheduledAt, 'LLL d, h:mm a') }}
  </span>

  <span class="flex-1 text-sm truncate text-n-slate-11 whitespace-nowrap">
    {{
      t('CAMPAIGN.BROADCAST.CARD.CAMPAIGN_DETAILS.RESULT', {
        sent: sentCount,
        replied: repliedCount,
      })
    }}
  </span>
</template>
