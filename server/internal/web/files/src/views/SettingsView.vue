<template>
  <div class="page-container">
    <div class="page-title-bar">
      <h2>同步配置</h2>
    </div>

    <el-card shadow="never" class="settings-card">
      <el-form label-position="top" class="settings-form">
        <!-- Device ID 优先：不依赖 token -->
        <el-divider content-position="left">
          <el-icon><Iphone /></el-icon>
          <span style="margin-left: 6px">设备标识</span>
        </el-divider>

        <el-form-item label="Device ID">
          <el-select
            v-model="cfg.deviceId"
            filterable
            allow-create
            default-first-option
            placeholder="点击刷新从服务端拉取，或直接手动输入"
            :loading="cfg.devicesLoading"
            style="width: 100%"
          >
            <el-option
              v-for="d in cfg.devices"
              :key="d.deviceId"
              :label="d.deviceId"
              :value="d.deviceId"
            >
              <span class="device-id">{{ d.deviceId }}</span>
              <span class="device-meta">{{ formatTime(d.syncTimestamp) }} · v{{ d.dataVersion }}</span>
            </el-option>
          </el-select>
          <el-button
            size="small"
            plain
            :icon="Refresh"
            @click="loadDevices"
            :loading="cfg.devicesLoading"
            style="margin-top: 8px"
          >
            刷新设备列表
          </el-button>
        </el-form-item>

        <el-alert
          type="info"
          :closable="false"
          show-icon
          title="Device ID 选项来自服务端 sync_meta 表（iOS 端至少上传过一次才会出现），刷新无需 Sync Token。"
        />

        <!-- Sync Token -->
        <el-divider content-position="left">
          <el-icon><Key /></el-icon>
          <span style="margin-left: 6px">同步密钥</span>
        </el-divider>

        <el-form-item label="Sync Token">
          <el-input
            v-model="cfg.syncToken"
            type="password"
            show-password
            placeholder="与服务端 SYNC_TOKEN 一致"
            autocomplete="off"
          />
        </el-form-item>
        <el-alert
          type="warning"
          :closable="false"
          show-icon
          title="Sync Token 仅在调用 /sync/* 与 /api/recipes 等 CRUD 时校验；选择 Device ID 时不再要求。"
        />

        <!-- 操作 -->
        <el-divider />
        <el-form-item>
          <el-space wrap>
            <el-button type="primary" :icon="Check" @click="save">保存</el-button>
            <el-button :icon="Connection" @click="testConnection" :loading="testing">测试连接</el-button>
            <el-button type="danger" plain :icon="Delete" @click="clear">清空配置</el-button>
          </el-space>
        </el-form-item>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import {
  Check,
  Connection,
  Delete,
  Iphone,
  Key,
  Refresh,
} from '@element-plus/icons-vue'
import { useConfigStore } from '@/stores/config'
import { syncApi } from '@/api/sync'
import { useToast } from '@/composables/useToast'

const cfg = useConfigStore()
const toast = useToast()
const testing = ref(false)

onMounted(() => {
  // 进入配置页即自动拉取一次设备列表（不再要求 token）
  loadDevices()
})

async function loadDevices() {
  try {
    await cfg.fetchDevices()
    if (cfg.devices.length === 0) {
      toast.warn('服务端暂无设备记录，请先在 iOS 端完成一次上传')
    }
  } catch (err) {
    toast.showError(err, '获取设备列表失败')
  }
}

function save() {
  cfg.save()
  ElMessage.success('配置已保存')
}

async function testConnection() {
  if (!cfg.deviceId) {
    toast.warn('请先选择 Device ID')
    return
  }
  cfg.save()
  testing.value = true
  try {
    const info = await syncApi.getInfo()
    ElMessage.success(`连接成功，共 ${info.totalCount} 条数据，最近同步：${formatTime(info.syncTimestamp)}`)
  } catch (err) {
    toast.showError(err, '连接失败')
  } finally {
    testing.value = false
  }
}

async function clear() {
  if (!(await toast.confirm('确认清空配置？此操作不可撤销。', '清空配置'))) return
  cfg.clear()
  ElMessage.success('配置已清空')
}

function formatTime(ts: number): string {
  if (!ts) return '—'
  return new Date(ts * 1000).toLocaleString('zh-Hans')
}
</script>

<style scoped lang="scss">
.settings-card {
  max-width: 720px;
}
.settings-form {
  max-width: 540px;
}
.device-id {
  float: left;
}
.device-meta {
  float: right;
  color: #8e8e93;
  font-size: 12px;
}
</style>
