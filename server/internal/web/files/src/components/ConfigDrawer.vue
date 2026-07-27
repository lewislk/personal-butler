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
      </el-form-item>
    </el-form>
  </el-drawer>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useConfigStore } from '@/stores/config'

const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: boolean): void }>()

const cfg = useConfigStore()

const visible = ref(props.modelValue)
watch(() => props.modelValue, (v) => (visible.value = v))
watch(visible, (v) => emit('update:modelValue', v))

function save() {
  cfg.save()
  ElMessage.success('配置已保存')
  visible.value = false
}
</script>
