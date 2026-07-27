<template>
  <div class="empty-state">
    <p class="big-emoji">{{ emoji }}</p>
    <p class="title">{{ title }}</p>
    <p v-if="hint" class="hint">{{ hint }}</p>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  emoji?: string
  title: string
  hint?: string
}>()
</script>

<style scoped lang="scss">
.empty-state {
  text-align: center;
  padding: 48px 24px;
  color: #8e8e93;
  background: #fff;
  border: 1px dashed #d1d1d6;
  border-radius: 8px;
}
.big-emoji {
  font-size: 48px;
  margin: 0 0 8px;
}
.title {
  margin: 0 0 4px;
  font-size: 14px;
}
.hint {
  margin: 0;
  font-size: 12px;
  color: #aeaeb2;
}
</style>
