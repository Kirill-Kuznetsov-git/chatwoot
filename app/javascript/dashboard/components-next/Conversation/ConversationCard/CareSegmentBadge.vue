<script setup>
// Support Care (SCC-102): значимость клиента отдельным значком, а не ещё одним тегом в общей строке.
// Сегмент приходит из Care в custom_attributes контакта (segment_label вида «🐋 Big Whale Seller»),
// показываем только эмодзи, полный текст — в подсказке. Рядовым сегментам значок не рисуем,
// иначе он был бы почти у каждого диалога и перестал бы что-либо значить.
import { computed } from 'vue';

const props = defineProps({
  contact: {
    type: Object,
    default: () => ({}),
  },
  conversation: {
    type: Object,
    default: () => ({}),
  },
});

const VALUABLE_WEIGHTS = ['Mega Whale', 'Big Whale', 'Whale', 'Big Fish'];
const VALUABLE_TIER = 'Big';

const attributes = computed(() => {
  const fromContact = props.contact?.customAttributes;
  if (fromContact && Object.keys(fromContact).length) return fromContact;
  return props.conversation?.meta?.sender?.customAttributes ?? {};
});

const read = key =>
  attributes.value[key] ??
  attributes.value[key.replace(/[A-Z]/g, m => `_${m.toLowerCase()}`)];

const label = computed(() => String(read('segmentLabel') ?? '').trim());

const isValuable = computed(() => {
  const weight = read('segmentWeight');
  const tier = read('segmentTier90d');
  return VALUABLE_WEIGHTS.includes(weight) || tier === VALUABLE_TIER;
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
    class="flex items-center justify-center flex-shrink-0 rounded-full size-5 bg-n-alpha-2 text-sm leading-none"
  >
    {{ emoji }}
  </div>
</template>
