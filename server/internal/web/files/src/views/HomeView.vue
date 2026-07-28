<template>
  <div class="page-container" v-loading="store.loading">
    <div class="page-title-bar">
      <h2>总览</h2>
      <el-button :icon="Refresh" @click="refresh" :loading="store.loading" plain>刷新</el-button>
    </div>

    <!-- 数据卡片 -->
    <el-row :gutter="16" class="stat-row">
      <el-col :xs="24" :sm="12" :md="8">
        <el-card shadow="hover" class="stat-card sync-card">
          <div class="card-head">
            <el-icon class="card-icon"><Connection /></el-icon>
            <span class="card-label">同步状态</span>
            <el-tag v-if="cfg.isConfigured && store.info" type="success" size="small" round>已同步</el-tag>
            <el-tag v-else-if="!cfg.isConfigured" type="warning" size="small" round>未配置</el-tag>
            <el-tag v-else type="info" size="small" round>尚未同步</el-tag>
          </div>
          <div v-if="!cfg.isConfigured" class="card-body">
            <el-empty :image-size="60" description="请先配置 Device ID">
              <el-button type="primary" size="small" @click="goSettings">立即配置</el-button>
            </el-empty>
          </div>
          <div v-else-if="store.info" class="card-body">
            <el-descriptions :column="1" size="small" border>
              <el-descriptions-item label="最近同步">{{ formatTime(store.info.syncTimestamp) }}</el-descriptions-item>
              <el-descriptions-item label="App 版本">{{ store.info.appVersion }}</el-descriptions-item>
              <el-descriptions-item label="数据版本">v{{ store.info.dataVersion }}</el-descriptions-item>
              <el-descriptions-item label="总条数">{{ store.info.totalCount }}</el-descriptions-item>
            </el-descriptions>
          </div>
          <div v-else class="card-body">
            <el-empty :image-size="60" description="尚未同步" />
          </div>
        </el-card>
      </el-col>

      <el-col :xs="24" :sm="12" :md="8">
        <el-card shadow="hover" class="stat-card">
          <div class="card-head">
            <el-icon class="card-icon"><KnifeFork /></el-icon>
            <span class="card-label">菜谱</span>
          </div>
          <div class="card-body center">
            <el-statistic :value="store.recipeCount" />
            <span class="stat-sub">条菜谱</span>
          </div>
          <div class="card-foot">
            <el-button type="primary" size="small" plain @click="goRecipes">立即管理</el-button>
          </div>
        </el-card>
      </el-col>

      <el-col :xs="24" :sm="12" :md="8">
        <el-card shadow="hover" class="stat-card">
          <div class="card-head">
            <el-icon class="card-icon"><Lock /></el-icon>
            <span class="card-label">密码</span>
          </div>
          <div class="card-body center">
            <el-statistic :value="store.passwordCount" />
            <span class="stat-sub">条密码记录</span>
          </div>
          <div class="card-foot">
            <el-button type="primary" size="small" plain @click="goPasswords">立即管理</el-button>
          </div>
        </el-card>
      </el-col>
    </el-row>

    <!-- 使用提示 -->
    <el-card shadow="never" class="tip-card">
      <template #header>
        <div class="card-head">
          <el-icon class="card-icon"><InfoFilled /></el-icon>
          <span class="card-label">使用提示</span>
        </div>
      </template>
      <el-alert
        type="warning"
        :closable="false"
        show-icon
        title="iOS 上传 → Web 编辑 → iOS 下载（推荐顺序）"
      >
        <ol class="tip-steps">
          <li>iOS 端先做一次<strong>上传</strong>，把本地状态推到服务端</li>
          <li>浏览器打开 /web，配置 Device ID + Token</li>
          <li>在 Web 端录入 / 编辑数据，保存到 DB</li>
          <li>iOS 端做<strong>下载</strong> → 本地数据被服务端数据全量替换</li>
        </ol>
      </el-alert>
      <el-alert
        type="error"
        :closable="false"
        show-icon
        title="⚠️ 注意 upload 会覆盖 Web 录入"
        style="margin-top: 12px"
      >
        <p>iOS 端 upload 是全量覆盖语义（DELETE WHERE device_id + INSERT）。如果 iOS 在 Web 录入后再 upload，会<strong>清空</strong> Web 录入的数据。</p>
        <p>请严格遵循「先 iOS upload → 再 Web 编辑 → 再 iOS download」的顺序。</p>
      </el-alert>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import {
  Connection,
  InfoFilled,
  KnifeFork,
  Lock,
  Refresh,
} from '@element-plus/icons-vue'
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

function refresh() {
  if (cfg.isConfigured) store.refresh()
}

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
.stat-row {
  margin-bottom: 16px;
}
.stat-card {
  margin-bottom: 16px;
  min-height: 240px;
  display: flex;
  flex-direction: column;

  :deep(.el-card__body) {
    flex: 1;
    display: flex;
    flex-direction: column;
  }
}
.sync-card {
  background: linear-gradient(135deg, #ffffff 0%, #f0f8ff 100%);
}
.card-head {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}
.card-icon {
  font-size: 18px;
  color: #007aff;
}
.card-label {
  font-weight: 600;
  font-size: 15px;
  flex: 1;
}
.card-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  min-height: 120px;
}
.card-body.center {
  align-items: center;
  gap: 4px;
}
.stat-sub {
  color: #8e8e93;
  font-size: 13px;
}
.card-foot {
  margin-top: 12px;
  text-align: right;
}
.tip-card {
  margin-top: 8px;
}
.tip-steps {
  margin: 8px 0 0;
  padding-left: 20px;
  line-height: 1.8;
}
.tip-steps li {
  font-size: 13px;
}
.tip-card p {
  margin: 4px 0;
  font-size: 13px;
}
</style>
