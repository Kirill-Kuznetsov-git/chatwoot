<script>
// Отбивка неавторизованному посетителю: живого оператора он не получает, ответ придёт
// письмом. Рендерится как сообщение поддержки (аватар и имя инбокса), но сообщением не
// является — текст берётся из i18n, поэтому приходит на языке виджета.
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import configMixin from '../mixins/configMixin';

export default {
  name: 'GuestDeliveryNotice',
  components: {
    Avatar,
  },
  mixins: [configMixin],
  computed: {
    senderName() {
      return this.channelConfig.websiteName;
    },
  },
};
</script>

<template>
  <div class="agent-message-wrap">
    <div class="agent-message">
      <div class="avatar-wrap">
        <div class="user-thumbnail-box">
          <Avatar
            :src="inboxAvatarUrl"
            :size="24"
            :name="senderName"
            rounded-full
          />
        </div>
      </div>
      <div class="message-wrap">
        <div class="chat-bubble agent bg-n-background dark:bg-n-solid-3">
          <div class="message-content whitespace-pre-line text-n-slate-12">
            {{ $t('STARPETS_WIDGET.GUEST_DELIVERY_NOTICE') }}
          </div>
        </div>
        <p class="agent-name text-n-slate-11">{{ senderName }}</p>
      </div>
    </div>
  </div>
</template>
