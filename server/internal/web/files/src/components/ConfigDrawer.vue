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
        type="info"
        :closable="false"
        show-icon
        title="v6 起单用户单设备，仅需 Sync Token 鉴权；服务端不再校验 X-Device-ID。"
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
  Key,
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
})

function save() {
  cfg.save()
  ElMessage.success('配置已保存')
  visible.value = false
}

async function testConnection() {
  if (!cfg.syncToken) {
    toast.warn('请先填写 Sync Token')
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
</style>
