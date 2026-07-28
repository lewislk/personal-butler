<template>
  <el-container class="app-shell">
    <el-aside :width="collapsed ? '64px' : '220px'" class="app-aside">
      <div class="brand">
        <span class="brand-emoji">🛎️</span>
        <transition name="fade">
          <span v-if="!collapsed" class="brand-text">PersonalButler</span>
        </transition>
      </div>
      <el-menu
        :default-active="route.name as string"
        :collapse="collapsed"
        router
        class="app-menu"
        background-color="transparent"
        text-color="#c9d1e0"
        active-text-color="#ffffff"
      >
        <el-menu-item index="home">
          <el-icon><Odometer /></el-icon>
          <template #title>总览</template>
        </el-menu-item>
        <el-menu-item index="recipes">
          <el-icon><KnifeFork /></el-icon>
          <template #title>烹饪管理</template>
        </el-menu-item>
        <el-menu-item index="passwords">
          <el-icon><Lock /></el-icon>
          <template #title>密码记录</template>
        </el-menu-item>
        <el-menu-item index="settings">
          <el-icon><Setting /></el-icon>
          <template #title>配置</template>
        </el-menu-item>
      </el-menu>
    </el-aside>

    <el-container>
      <el-header class="app-header">
        <div class="header-left">
          <el-icon class="collapse-btn" @click="collapsed = !collapsed">
            <Fold v-if="!collapsed" />
            <Expand v-else />
          </el-icon>
          <el-breadcrumb :separator-icon="ArrowRight" class="page-crumb">
            <el-breadcrumb-item :to="{ path: '/' }">首页</el-breadcrumb-item>
            <el-breadcrumb-item v-if="route.meta.title && route.name !== 'home'">
              {{ route.meta.title }}
            </el-breadcrumb-item>
          </el-breadcrumb>
        </div>
        <div class="header-right">
          <el-tag v-if="cfg.isConfigured" type="success" effect="light" round size="small">
            <el-icon style="vertical-align: middle; margin-right: 4px"><CircleCheck /></el-icon>
            {{ cfg.deviceId.slice(0, 8) }}…
          </el-tag>
          <el-tag v-else type="warning" effect="light" round size="small">未配置</el-tag>
          <el-tooltip content="同步配置" placement="bottom">
            <el-button :icon="Setting" circle @click="drawerVisible = true" />
          </el-tooltip>
        </div>
      </el-header>

      <el-main class="app-main">
        <router-view />
      </el-main>
    </el-container>

    <ConfigDrawer v-model="drawerVisible" />
  </el-container>
</template>

<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ElMessage } from 'element-plus'
import {
  ArrowRight,
  CircleCheck,
  Expand,
  Fold,
  KnifeFork,
  Lock,
  Odometer,
  Setting,
} from '@element-plus/icons-vue'
import ConfigDrawer from '@/components/ConfigDrawer.vue'
import { useConfigStore } from '@/stores/config'

const drawerVisible = ref(false)
const collapsed = ref(false)
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
}
.app-aside {
  background: linear-gradient(180deg, #1f2937 0%, #111827 100%);
  transition: width 0.25s ease;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 18px 20px;
  color: #fff;
  height: 56px;
  box-sizing: border-box;
  white-space: nowrap;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}
.brand-emoji {
  font-size: 22px;
  flex-shrink: 0;
}
.brand-text {
  font-size: 16px;
  font-weight: 600;
  letter-spacing: 0.3px;
}
.app-menu {
  flex: 1;
  border-right: none !important;
  padding: 12px 8px;

  :deep(.el-menu-item) {
    border-radius: 8px;
    margin-bottom: 4px;
    height: 44px;
    line-height: 44px;

    &:hover {
      background: rgba(255, 255, 255, 0.06) !important;
      color: #fff !important;
    }
    &.is-active {
      background: linear-gradient(135deg, #007aff 0%, #4d9bff 100%) !important;
      color: #fff !important;
      box-shadow: 0 4px 12px rgba(0, 122, 255, 0.35);
    }
  }
}
.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border-bottom: 1px solid #ebeef5;
  padding: 0 24px;
  height: 56px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
  z-index: 10;
}
.header-left {
  display: flex;
  align-items: center;
  gap: 16px;
}
.collapse-btn {
  font-size: 20px;
  color: #5e6470;
  cursor: pointer;
  transition: color 0.15s;

  &:hover {
    color: #007aff;
  }
}
.page-crumb {
  font-size: 14px;
}
.header-right {
  display: flex;
  align-items: center;
  gap: 12px;
}
.app-main {
  padding: 0;
  background: #f0f2f5;
}
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
