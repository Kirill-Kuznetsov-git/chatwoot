<script setup>
// Support Care (SCC-102): сегмент клиента читается прямо в строке, без наведения.
// Цвет чипа = значимость по обороту (чем насыщеннее, тем крупнее клиент), буква = роль:
// B — покупатель, S — продавец, T — трейдер, N — новичок. Полное название в подсказке.
// Рядовым клиентам чип не рисуем: иначе он был бы почти у каждого обращения и перестал бы работать.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  conversation: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

// Порядок важен: от самого крупного к младшему.
const WEIGHT_STYLES = {
  'Mega Whale': 'bg-n-iris-9 text-white',
  'Big Whale': 'bg-n-blue-9 text-white',
  Whale: 'bg-n-teal-9 text-white',
  'Big Fish': 'bg-n-slate-4 text-n-slate-12',
};
const ROLE_LETTERS = { Buyer: 'B', Seller: 'S', Trader: 'T', Newcomer: 'N' };
const BIG_TIER = 'Big';

const segment = computed(
  () => props.conversation?.careSegment ?? props.conversation?.care_segment ?? {}
);

const weight = computed(() => segment.value.weight ?? null);
const tier = computed(() => segment.value.tier90d ?? segment.value.tier_90d ?? null);
const role = computed(() => segment.value.role ?? null);

// Big Fish попадает в список и по 90-дневному уровню: активный середняк тоже важен оператору.
const style = computed(() => {
  if (WEIGHT_STYLES[weight.value]) return WEIGHT_STYLES[weight.value];
  return tier.value === BIG_TIER ? WEIGHT_STYLES['Big Fish'] : null;
});

const letter = computed(() => ROLE_LETTERS[role.value] ?? '•');

const tooltip = computed(() => {
  const label = String(segment.value.label ?? '').trim();
  const roleName = role.value
    ? t(`CARE_SEGMENT.ROLE.${String(role.value).toUpperCase()}`)
    : '';
  return [label, roleName].filter(Boolean).join(' · ');
});

const show = computed(() => Boolean(style.value));
</script>

<template>
  <div
    v-if="show"
    v-tooltip.top="tooltip"
    class="inline-flex items-center justify-center flex-shrink-0 rounded-md size-[18px] text-[10px] font-semibold leading-none tabular-nums"
    :class="style"
  >
    {{ letter }}
  </div>
</template>
