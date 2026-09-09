<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNumberFormatter } from 'shared/composables/useNumberFormatter';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  currentPage: {
    type: Number,
    required: true,
  },
  // null означает «общее число неизвестно»: некоторые списки не считают total,
  // потому что точный COUNT по таблице слишком дорог. В этом режиме подвал
  // ориентируется на hasMore и itemsOnPage.
  totalItems: {
    type: Number,
    default: null,
  },
  itemsPerPage: {
    type: Number,
    default: 16,
  },
  currentPageInfo: {
    type: String,
    default: '',
  },
  // Есть ли ещё страницы. Используется только когда totalItems неизвестен.
  hasMore: {
    type: Boolean,
    default: false,
  },
  // Сколько записей реально пришло на текущей странице. Нужно, чтобы на последней
  // странице показать честный диапазон, а не округлённый до размера страницы.
  itemsOnPage: {
    type: Number,
    default: null,
  },
  // Ключ перевода для диапазона без общего числа.
  unknownTotalPageInfo: {
    type: String,
    default: '',
  },
});
const emit = defineEmits(['update:currentPage']);
const { t } = useI18n();
const { formatCompactNumber, formatFullNumber } = useNumberFormatter();

const isTotalKnown = computed(() => Number.isFinite(props.totalItems));

const totalPages = computed(() =>
  isTotalKnown.value ? Math.ceil(props.totalItems / props.itemsPerPage) : null
);
const startItem = computed(
  () => (props.currentPage - 1) * props.itemsPerPage + 1
);
const endItem = computed(() => {
  if (isTotalKnown.value) {
    return Math.min(startItem.value + props.itemsPerPage - 1, props.totalItems);
  }
  const onPage = Number.isFinite(props.itemsOnPage)
    ? props.itemsOnPage
    : props.itemsPerPage;
  return startItem.value + Math.max(onPage, 1) - 1;
});
const isFirstPage = computed(() => props.currentPage === 1);
const isLastPage = computed(() =>
  isTotalKnown.value ? props.currentPage === totalPages.value : !props.hasMore
);
const changePage = newPage => {
  if (newPage < 1) return;
  if (isTotalKnown.value && newPage > totalPages.value) return;
  emit('update:currentPage', newPage);
};

const currentPageInformation = computed(() => {
  if (!isTotalKnown.value) {
    const key = props.unknownTotalPageInfo || 'PAGINATION_FOOTER.SHOWING_RANGE';
    return t(key, {
      startItem: formatFullNumber(startItem.value),
      endItem: formatFullNumber(endItem.value),
    });
  }

  const translationKey = props.currentPageInfo || 'PAGINATION_FOOTER.SHOWING';
  return t(
    translationKey,
    {
      startItem: formatFullNumber(startItem.value),
      endItem: formatFullNumber(endItem.value),
      totalItems: formatCompactNumber(props.totalItems),
    },
    Number(props.totalItems)
  );
});

// Без общего числа страниц надпись «из N страниц» показать нечего.
const pageInfo = computed(() => {
  if (!isTotalKnown.value) return '';

  return t(
    'PAGINATION_FOOTER.CURRENT_PAGE_INFO',
    {
      currentPage: '',
      totalPages: formatCompactNumber(totalPages.value),
    },
    Number(totalPages.value)
  );
});
</script>

<template>
  <div
    class="flex justify-between h-[3.375rem] w-full border-t border-n-weak mx-auto bg-n-surface-1 py-3 px-6 items-center before:absolute before:inset-x-0 before:-top-4 before:bg-gradient-to-t before:from-n-surface-1 before:from-0% before:to-transparent before:h-4 before:pointer-events-none"
  >
    <div class="flex items-center gap-3">
      <span class="min-w-0 text-body-main line-clamp-1 text-n-slate-11">
        {{ currentPageInformation }}
      </span>
    </div>
    <div class="flex items-center gap-2">
      <Button
        icon="i-lucide-chevrons-left"
        variant="ghost"
        size="sm"
        color="slate"
        class="!w-8 !h-6"
        :disabled="isFirstPage"
        @click="changePage(1)"
      />
      <Button
        icon="i-lucide-chevron-left"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-8 !h-6"
        :disabled="isFirstPage"
        @click="changePage(currentPage - 1)"
      />
      <div class="inline-flex items-center gap-2 text-sm">
        <span
          class="px-3 tabular-nums py-0.5 font-420 bg-n-input-background text-body-main text-n-slate-12 rounded-md"
        >
          {{ formatFullNumber(currentPage) }}
        </span>
        <span class="truncate text-body-main text-n-slate-11">
          {{ pageInfo }}
        </span>
      </div>
      <Button
        icon="i-lucide-chevron-right"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-8 !h-6"
        :disabled="isLastPage"
        @click="changePage(currentPage + 1)"
      />
      <Button
        v-if="isTotalKnown"
        icon="i-lucide-chevrons-right"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-8 !h-6"
        :disabled="isLastPage"
        @click="changePage(totalPages)"
      />
    </div>
  </div>
</template>
