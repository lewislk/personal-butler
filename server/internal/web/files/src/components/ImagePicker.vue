<template>
  <div class="image-picker">
    <img v-if="previewSrc" :src="previewSrc" class="icon-preview" alt="预览" />
    <el-upload
      :auto-upload="false"
      :show-file-list="false"
      accept="image/jpeg,image/png"
      :on-change="onChange"
    >
      <el-button size="small">选择图片</el-button>
    </el-upload>
    <el-button v-if="previewSrc" size="small" @click="clear">清除</el-button>
  </div>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import type { UploadFile } from 'element-plus'
import { useImageCompress } from '@/composables/useImageCompress'
import { useToast } from '@/composables/useToast'

const props = defineProps<{ modelValue?: string | null }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: string | null): void }>()

const { fileToBase64 } = useImageCompress()
const toast = useToast()
const previewSrc = ref<string>('')

// 初始化预览（编辑场景从 base64 还原 dataURL）
watch(
  () => props.modelValue,
  (v) => {
    if (v) {
      previewSrc.value = `data:image/jpeg;base64,${v}`
    } else {
      previewSrc.value = ''
    }
  },
  { immediate: true }
)

async function onChange(file: UploadFile) {
  if (!file.raw) return
  try {
    const base64 = await fileToBase64(file.raw)
    previewSrc.value = `data:image/jpeg;base64,${base64}`
    emit('update:modelValue', base64)
  } catch (err) {
    toast.showError(err, '图片处理失败')
  }
}

function clear() {
  previewSrc.value = ''
  emit('update:modelValue', null)
}
</script>

<style scoped lang="scss">
.image-picker {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.icon-preview {
  width: 56px;
  height: 56px;
  border-radius: 8px;
  object-fit: cover;
  border: 1px solid #d1d1d6;
}
</style>
