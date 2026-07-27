<template>
  <div class="home-page">
    <el-row :gutter="16" v-loading="store.loading">
      <el-col :xs="24" :sm="12" :md="8">
        <el-card class="stat-card">
          <template #header>同步状态</template>
          <template v-if="!cfg.isConfigured">
            <p class="muted">请先配置 Device ID</p>
            <el-button type="primary" size="small" @click="goSettings">立即配置</el-button>
          </template>
          <template v-else-if="store.info">
            <p>最近同步：<strong>{{ formatTime(store.info.syncTimestamp) }}</strong></p>
            <p>App 版本：{{ store.info.appVersion }}</p>
            <p>数据版本：v{{ store.info.dataVersion }}</p>
            <p>总条数：{{ store.info.totalCount }}</p>
          </template>
          <template v-else>
            <p class="muted">尚未同步</p>
          </template>
        </el-card>
      </el-col>

      <el-col :xs="24" :sm="12" :md="8">
        <el-card class="stat-card">
          <template #header>菜谱</template>
          <p class="big-num">{{ store.recipeCount }}</p>
          <p class="muted">条菜谱</p>
          <el-button type="primary" size="small" @click="goRecipes">立即管理</el-button>
        </el-card>
      </el-col>

      <el-col :xs="24" :sm="12" :md="8">
        <el-card class="stat-card">
          <template #header>密码</template>
          <p class="big-num">{{ store.passwordCount }}</p>
          <p class="muted">条密码记录</p>
          <el-button type="primary" size="small" @click="goPasswords">立即管理</el-button>
        </el-card>
      </el-col>
    </el-row>

    <el-card class="tip-card">
      <template #header>使用提示</template>
      <el-collapse>
        <el-collapse-item title="iOS 上传 → Web 编辑 → iOS 下载（推荐顺序）" name="1">
          <p>1. iOS 端先做一次<strong>上传</strong>，把本地状态推到服务端</p>
          <p>2. 浏览器打开 /web，配置 Device ID + Token</p>
          <p>3. 在 Web 端录入 / 编辑数据，保存到 DB</p>
          <p>4. iOS 端做<strong>下载</strong> → 本地数据被服务端数据全量替换</p>
        </el-collapse-item>
        <el-collapse-item title="⚠️ 注意 upload 会覆盖 Web 录入" name="2">
          <p>iOS 端 upload 是全量覆盖语义（DELETE WHERE device_id + INSERT）。如果 iOS 在 Web 录入后再 upload，会<strong>清空</strong> Web 录入的数据。</p>
          <p>请严格遵循「先 iOS upload → 再 Web 编辑 → 再 iOS download」的顺序。</p>
        </el-collapse-item>
      </el-collapse>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useOverviewStore } from '@/stores/overview'
import { useConfigStore } from '@/stores/config'

const router = useRouter()
const store = useOverviewStore()
const cfg = useConfigStore()

onMounted(() => {
  if (cfg.isConfigured) {
    store.refresh()
  }
})

function goSettings() {
  router.push('/settings')
}
function goRecipes() {
  router.push('/recipes')
}
function goPasswords() {
  router.push('/passwords')
}
function formatTime(ts: number): string {
  return new Date(ts * 1000).toLocaleString('zh-Hans')
}
</script>

<style scoped lang="scss">
.home-page {
  padding: 24px;
}
.stat-card {
  margin-bottom: 16px;
  min-height: 200px;
}
.big-num {
  font-size: 36px;
  font-weight: 600;
  margin: 8px 0;
}
.muted {
  color: #8e8e93;
  font-size: 13px;
}
.tip-card {
  margin-top: 16px;
}
.tip-card p {
  margin: 6px 0;
  font-size: 13px;
}
</style>
