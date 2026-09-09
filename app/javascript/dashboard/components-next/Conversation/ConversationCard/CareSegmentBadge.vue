<script setup>
// Support Care (SCC-102): значимость клиента отдельным значком, а не ещё одним тегом в общей строке.
// Сегмент приходит в диалоге полем care_segment (метка вида «🐋 Big Whale Seller»), показываем только
// эмодзи, полное название — в подсказке. Рядовым сегментам значка не рисуем, иначе он был бы почти
// у каждого обращения и перестал бы что-либо значить.
import { computed } from 'vue';

const props = defineProps({
  conversation: {
    type: Object,
    default: () => ({}),
  },
});

const VALUABLE_WEIGHTS = ['Mega Whale', 'Big Whale', 'Whale', 'Big Fish'];
const VALUABLE_TIER = 'Big';

const segment = computed(
  () => props.conversation?.careSegment ?? props.conversation?.care_segment ?? {}
);

const label = computed(() => String(segment.value.label ?? '').trim());

const isValuable = computed(() => {
  const tier = segment.value.tier90d ?? segment.value.tier_90d;
  return VALUABLE_WEIGHTS.includes(segment.value.weight) || tier === VALUABLE_TIER;
});

// Первый токен метки — эмодзи веса; если его нет, значок не рисуем.
const emoji = computed(() => {
  const first = label.value.split(' ')[0] ?? '';
  return first.length > 0 && first.length <= 3 ? first : '';
});

const show = computed(() => isValuable.value && emoji.value !== '');
</script>

<template>
  <div
    v-if="show"
    v-tooltip.top="label"
    class="flex items-center justify-center flex-shrink-0 size-5 text-sm leading-none"
  >
    {{ emoji }}
  </div>
</template>
