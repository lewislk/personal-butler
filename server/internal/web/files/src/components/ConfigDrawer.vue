<template>
  <el-drawer v-model="visible" title="同步配置" direction="rtl" size="380px">
    <el-form label-position="top">
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
        在 iOS 端「我的 → 局域网同步」可看到 Device ID 前缀；Token 与服务端 SYNC_TOKEN 一致即可。
      </p>
    </el-form>
  </el-drawer>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
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
watch(visible, (v) => emit('update:modelValue', v))

function save() {
  cfg.save()
  ElMessage.success('配置已保存')
  visible.value = false
}

async function testConnection() {
  if (!cfg.deviceId) {
    toast.warn('请先填写 Device ID')
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
  return new Date(ts * 1000).toLocaleString('zh-Hans')
}
</script>

<style scoped>
.hint {
  color: #8e8e93;
  font-size: 12px;
  margin: 8px 0 0;
}
</style>
