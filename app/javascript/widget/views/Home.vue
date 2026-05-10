<script>
import ConversationCardList from 'widget/components/ConversationCardList.vue';
import ArticleContainer from '../components/pageComponents/Home/Article/ArticleContainer.vue';
export default {
  name: 'Home',
  components: {
    ArticleContainer,
    ConversationCardList,
  },
};
</script>

<template>
  <div class="z-50 flex flex-col justify-end flex-1 w-full p-4 gap-4">
    <ConversationCardList />
    <ArticleContainer />
  </div>
</template>
