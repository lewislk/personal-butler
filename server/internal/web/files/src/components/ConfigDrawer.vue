<template>
  <el-drawer
    v-model="visible"
    title="同步配置"
    direction="rtl"
    size="400px"
    :with-header="true"
  >
    <el-form label-position="top" class="drawer-form">
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
            <span class="device-meta">{{ formatTime(d.syncTimestamp) }}</span>
          </el-option>
        </el-select>
        <el-button
          size="small"
          plain
          :icon="Refresh"
          @click="loadDevices"
          :loading="cfg.devicesLoading"
          style="margin-top: 8px; width: 100%"
        >
          刷新设备列表
        </el-button>
      </el-form-item>

      <el-alert
        type="info"
        :closable="false"
        show-icon
        title="Device ID 选项来自服务端 sync_meta 表，刷新无需 Sync Token。"
        style="margin-bottom: 12px"
      />

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

      <el-divider />

      <el-form-item>
        <el-space wrap>
          <el-button type="primary" :icon="Check" @click="save">保存</el-button>
          <el-button :icon="Connection" @click="testConnection" :loading="testing">测试</el-button>
          <el-button type="danger" plain :icon="Delete" @click="clear">清空</el-button>
        </el-space>
      </el-form-item>
    </el-form>
  </el-drawer>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
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

const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: boolean): void }>()

const cfg = useConfigStore()
const toast = useToast()
const testing = ref(false)

const visible = ref(props.modelValue)
watch(() => props.modelValue, (v) => (visible.value = v))
watch(visible, (v) => {
  emit('update:modelValue', v)
  // 抽屉打开时若 device 列表为空，自动拉取一次（不再要求 token）
  if (v && cfg.devices.length === 0) {
    loadDevices()
  }
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
  visible.value = false
}

async function testConnection() {
  if (!cfg.deviceId) {
    toast.warn('请先选择 Device ID')
    return
  }
  cfg.save() // 测试前先持久化，让拦截器能读到
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

<style scoped>
.drawer-form {
  padding: 0 4px;
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
