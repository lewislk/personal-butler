<template>
  <header class="app-header">
    <div class="brand">
      <span class="brand-emoji">🛎️</span>
      <h1>{{ pageTitle }}</h1>
    </div>
    <el-menu
      mode="horizontal"
      :default-active="route.name as string"
      :ellipsis="false"
      router
      class="nav-menu"
    >
      <el-menu-item index="home">总览</el-menu-item>
      <el-menu-item index="recipes">烹饪</el-menu-item>
      <el-menu-item index="passwords">密码</el-menu-item>
      <el-menu-item index="settings">配置</el-menu-item>
    </el-menu>
    <el-button class="cfg-btn" :icon="Setting" circle @click="openDrawer" />
  </header>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { Setting } from '@element-plus/icons-vue'

const route = useRoute()
const pageTitle = computed(() => (route.meta.title as string) || 'PersonalButler')

const emit = defineEmits<{ (e: 'open-drawer'): void }>()
function openDrawer() {
  emit('open-drawer')
}
</script>

<style scoped lang="scss">
.app-header {
  display: flex;
  align-items: center;
  gap: 24px;
  padding: 0 24px;
  background: #fff;
  border-bottom: 1px solid #e5e5ea;
  position: sticky;
  top: 0;
  z-index: 10;
  height: 56px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}
.brand-emoji {
  font-size: 22px;
}
.brand h1 {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
}
.nav-menu {
  flex: 1;
  border-bottom: none !important;
}
.cfg-btn {
  flex-shrink: 0;
}
</style>
