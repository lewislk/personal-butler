<template>
  <div class="settings-page">
    <el-card>
      <template #header>同步配置</template>
      <el-form label-position="top" class="settings-form">
        <el-form-item label="Device ID">
          <el-input v-model="cfg.deviceId" placeholder="例如：8F5B2A3C-..." autocomplete="off" />
        </el-form-item>
        <el-form-item label="Sync Token">
          <el-input v-model="cfg.syncToken" type="password" show-password placeholder="与服务端 SYNC_TOKEN 一致" autocomplete="off" />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="save">保存</el-button>
          <el-button @click="testConnection" :loading="testing">测试连接</el-button>
          <el-button type="danger" plain @click="clear">清空配置</el-button>
        </el-form-item>
        <p class="hint">
          Device ID 与 iOS 端 AppSyncConfig.deviceID 一致；Token 与服务端 SYNC_TOKEN 环境变量一致。两项保存在浏览器 localStorage。
        </p>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { ElMessage } from 'element-plus'
import { useConfigStore } from '@/stores/config'
import { syncApi } from '@/api/sync'
import { useToast } from '@/composables/useToast'

const cfg = useConfigStore()
const toast = useToast()
const testing = ref(false)

function save() {
  cfg.save()
  ElMessage.success('配置已保存')
}

async function testConnection() {
  if (!cfg.deviceId) {
    toast.warn('请先填写 Device ID')
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
  return new Date(ts * 1000).toLocaleString('zh-Hans')
}
</script>

<style scoped lang="scss">
.settings-page {
  padding: 24px;
  max-width: 720px;
  margin: 0 auto;
}
.settings-form {
  max-width: 480px;
}
.hint {
  color: #8e8e93;
  font-size: 12px;
  margin: 8px 0 0;
}
</style>
