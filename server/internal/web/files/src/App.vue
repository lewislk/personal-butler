<template>
  <div class="app-shell">
    <AppHeader @open-drawer="drawerVisible = true" />
    <main class="app-main">
      <router-view />
    </main>
    <ConfigDrawer v-model="drawerVisible" />
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ElMessage } from 'element-plus'
import AppHeader from '@/components/AppHeader.vue'
import ConfigDrawer from '@/components/ConfigDrawer.vue'
import { useConfigStore } from '@/stores/config'

const drawerVisible = ref(false)
const cfg = useConfigStore()
const route = useRoute()

// 进入任意页面时，若 deviceId 为空 → 自动唤起配置抽屉
onMounted(() => {
  if (!cfg.isConfigured) {
    drawerVisible.value = true
    ElMessage.warning('请先配置 Device ID')
  }
})

// 切换路由时滚动到顶部
watch(() => route.path, () => window.scrollTo(0, 0))
</script>

<style scoped lang="scss">
.app-shell {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}
.app-main {
  flex: 1;
}
</style>
