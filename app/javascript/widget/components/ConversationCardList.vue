<script>
import { mapActions, mapGetters, mapMutations } from 'vuex';
import { useRouter } from 'vue-router';
import configMixin from 'widget/mixins/configMixin';
import { IFrameHelper } from 'widget/helpers/utils';
import { CHATWOOT_ON_START_CONVERSATION } from 'widget/constants/sdkEvents';
import {
  L1_LABEL_PREFIX,
  L2_LABEL_PREFIX,
  hasLabelWithPrefix,
} from 'widget/constants/levels';

export default {
  name: 'ConversationCardList',
  mixins: [configMixin],
  setup() {
    const router = useRouter();
    return { router };
  },
  computed: {
    ...mapGetters({
      records: 'conversationList/getAll',
      hasL1: 'conversationList/hasL1Conversation',
      widgetColor: 'appConfig/getWidgetColor',
      activeId: 'appConfig/getActiveConversationId',
    }),
    sortedRecords() {
      return [...this.records].sort(
        (a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0)
      );
    },
    canStartNew() {
      return !this.hasL1;
    },
  },
  mounted() {
    this.fetchAll();
  },
  methods: {
    ...mapActions('conversationList', ['fetchAll']),
    ...mapActions('appConfig', ['setActiveConversationId']),
    ...mapActions('conversation', ['fetchOldConversations']),
    ...mapActions('conversationAttributes', [
      'getAttributes',
      'clearConversationAttributes',
    ]),
    ...mapMutations('conversation', ['clearConversations']),
    levelOf(labels) {
      if (hasLabelWithPrefix(labels, L2_LABEL_PREFIX)) return 'L2';
      if (hasLabelWithPrefix(labels, L1_LABEL_PREFIX)) return 'L1';
      return null;
    },
    categoryOf(labels) {
      if (!Array.isArray(labels)) return '';
      const tagged = labels.find(
        l =>
          l &&
          (l.startsWith(`${L1_LABEL_PREFIX}_`) ||
            l.startsWith(`${L2_LABEL_PREFIX}_`))
      );
      if (!tagged) return '';
      const parts = tagged.split('_');
      parts.shift();
      return parts.join(' ').replace(/\b\w/g, c => c.toUpperCase());
    },
    previewOf(conv) {
      const text = conv?.last_message?.content || '';
      const trimmed = text.replace(/\s+/g, ' ').trim();
      return trimmed.length > 80 ? `${trimmed.slice(0, 77)}…` : trimmed;
    },
    formatTime(ts) {
      if (!ts) return '';
      const diffSec = Math.max(0, Math.floor(Date.now() / 1000 - ts));
      if (diffSec < 60) return `${diffSec}s`;
      if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m`;
      if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h`;
      return `${Math.floor(diffSec / 86400)}d`;
    },
    async openConversation(conv) {
      await this.setActiveConversationId(conv.id);
      this.clearConversations();
      this.clearConversationAttributes();
      // Re-fetch attributes and messages for the now-active conversation.
      // Both calls will pass conversation_id via axios interceptor.
      await this.getAttributes();
      await this.fetchOldConversations();
      this.router.replace({ name: 'messages' });
    },
    startNew() {
      if (!this.canStartNew) return;
      // Detach from any currently-active conversation so the next message
      // creates a fresh one on the backend.
      this.setActiveConversationId(null);
      this.clearConversations();
      this.clearConversationAttributes();
      IFrameHelper.sendMessage({
        event: 'onEvent',
        eventIdentifier: CHATWOOT_ON_START_CONVERSATION,
        data: { hasConversation: false },
      });
      if (this.preChatFormEnabled) {
        return this.router.replace({ name: 'prechat-form' });
      }
      return this.router.replace({ name: 'messages' });
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-3 w-full">
    <button
      type="button"
      class="w-full inline-flex items-center justify-center gap-2 rounded-xl px-5 py-3 font-medium text-sm shadow outline-1 outline outline-n-container"
      :class="
        canStartNew
          ? 'cursor-pointer text-white'
          : 'cursor-not-allowed text-n-slate-9 bg-n-background dark:bg-n-solid-2'
      "
      :style="canStartNew ? { backgroundColor: widgetColor } : {}"
      :disabled="!canStartNew"
      @click="startNew"
    >
      <i class="i-lucide-plus size-4" />
      <span>{{ $t('START_NEW_CONVERSATION') }}</span>
    </button>

    <p
      v-if="!canStartNew"
      class="text-xs text-n-slate-11 dark:text-n-slate-9 -mt-1 px-1"
    >
      {{ $t('L1_ALREADY_OPEN_HINT') }}
    </p>

    <button
      v-for="conv in sortedRecords"
      :key="conv.id"
      type="button"
      class="w-full text-left flex flex-col gap-1 shadow outline-1 outline outline-n-container rounded-xl bg-n-background dark:bg-n-solid-2 px-5 py-4 hover:bg-n-slate-2 dark:hover:bg-n-solid-3 transition-colors cursor-pointer"
      :class="{
        'ring-2': conv.id === activeId,
      }"
      :style="conv.id === activeId ? { '--tw-ring-color': widgetColor } : {}"
      @click="openConversation(conv)"
    >
      <div class="flex justify-between items-start gap-2">
        <span class="font-medium text-n-slate-12 text-sm">
          <template v-if="levelOf(conv.labels) === 'L2'">
            {{ $t('CONVERSATION_LEVEL_L2') }}
          </template>
          <template v-else-if="levelOf(conv.labels) === 'L1'">
            {{ $t('CONVERSATION_LEVEL_L1') }}
          </template>
          <template v-else>
            {{ $t('CONVERSATION_GENERIC') }}
          </template>
          <span v-if="categoryOf(conv.labels)" class="font-normal text-n-slate-11">
            · {{ categoryOf(conv.labels) }}
          </span>
        </span>
        <span class="text-xs text-n-slate-11">
          {{ formatTime(conv.last_activity_at) }}
        </span>
      </div>
      <div
        v-if="previewOf(conv)"
        class="text-sm text-n-slate-11 dark:text-n-slate-9 line-clamp-2"
      >
        {{ previewOf(conv) }}
      </div>
    </button>
  </div>
</template>
