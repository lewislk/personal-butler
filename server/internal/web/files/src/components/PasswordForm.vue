<template>
  <el-card class="password-form-card">
    <el-form label-position="top" @submit.prevent="onSubmit">
      <el-form-item label="平台名称" required>
        <el-input v-model="form.platform" placeholder="GitHub" required />
      </el-form-item>

      <el-form-item label="账号" required>
        <el-input v-model="form.account" placeholder="alice@example.com" required />
      </el-form-item>

      <el-form-item label="密码" required>
        <div class="password-row">
          <el-input v-model="form.passwordPlain" type="password" show-password placeholder="••••••••" required />
          <el-button @click="generatePassword">生成随机</el-button>
        </div>
      </el-form-item>

      <el-form-item label="分类">
        <el-select v-model="form.category">
          <el-option label="社交" value="social" />
          <el-option label="办公" value="office" />
          <el-option label="金融" value="finance" />
          <el-option label="自定义" value="custom" />
        </el-select>
      </el-form-item>

      <el-form-item label="展示辅文">
        <el-input v-model="form.typeText" placeholder="例如：社交 · 常用" />
      </el-form-item>

      <div class="form-actions">
        <el-button type="primary" :loading="saving" @click="onSubmit">保存</el-button>
        <el-button @click="onCancel">取消</el-button>
        <el-button v-if="isEdit" type="danger" @click="onDelete">删除</el-button>
      </div>
    </el-form>
  </el-card>
</template>

<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { usePasswordsStore, passwordErrorMsg } from '@/stores/passwords'
import { useToast } from '@/composables/useToast'
import type { Password, PasswordInput } from '@/types/password'

const props = defineProps<{ password: Password | null }>()
const emit = defineEmits<{ (e: 'saved', id: string): void; (e: 'cancel'): void; (e: 'delete'): void }>()

const store = usePasswordsStore()
const toast = useToast()
const saving = ref(false)

const isEdit = computed(() => !!props.password)

interface FormState {
  id?: string
  platform: string
  account: string
  passwordPlain: string
  typeText: string
  category: string
}

function emptyForm(): FormState {
  return {
    platform: '',
    account: '',
    passwordPlain: '',
    typeText: '',
    category: 'social',
  }
}

const form = reactive<FormState>(emptyForm())

watch(
  () => props.password,
  (p) => {
    // 显式重置 id，避免上一次编辑/新建残留导致下一次新建走 update 分支覆盖旧记录
    form.id = undefined
    Object.assign(form, emptyForm())
    if (p) {
      form.id = p.id
      form.platform = p.platform
      form.account = p.account
      form.passwordPlain = p.passwordPlain
      form.typeText = p.typeText
      form.category = p.category || 'social'
    }
  },
  { immediate: true }
)

// crypto.getRandomValues 生成 12 位（大写+小写+数字+特殊符号各 3 位）
function generatePassword() {
  const upper = 'ABCDEFGHJKMNPQRSTUVWXYZ'
  const lower = 'abcdefghijkmnpqrstuvwxyz'
  const digit = '23456789'
  const special = '!@#$%^&*-_=+'
  const pools = [upper, lower, digit, special]
  const out: string[] = []
  const buf = new Uint32Array(12)
  crypto.getRandomValues(buf)
  // 先从每个池子各取 3 位
  for (let p = 0; p < 4; p++) {
    for (let i = 0; i < 3; i++) {
      out.push(pools[p][buf[p * 3 + i] % pools[p].length])
    }
  }
  // 简单洗牌
  for (let i = out.length - 1; i > 0; i--) {
    const j = buf[i] % (i + 1)
    ;[out[i], out[j]] = [out[j], out[i]]
  }
  form.passwordPlain = out.join('')
}

async function onSubmit() {
  if (!form.platform.trim()) {
    toast.warn('请填写平台名称')
    return
  }
  if (!form.account.trim()) {
    toast.warn('请填写账号')
    return
  }
  if (!form.passwordPlain) {
    toast.warn('请填写密码')
    return
  }
  saving.value = true
  try {
    const payload: PasswordInput = {
      id: form.id,
      platform: form.platform.trim(),
      account: form.account.trim(),
      passwordPlain: form.passwordPlain,
      typeText: form.typeText,
      category: form.category,
    }
    let savedId: string
    if (payload.id) {
      await store.update(payload.id, payload)
      savedId = payload.id
    } else {
      savedId = await store.create(payload)
    }
    toast.success('已保存')
    emit('saved', savedId)
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  } finally {
    saving.value = false
  }
}

function onCancel() {
  emit('cancel')
}

async function onDelete() {
  if (!form.id) return
  if (!(await toast.confirm('确认删除该密码记录？该操作不可撤销。', '删除确认'))) return
  try {
    await store.remove(form.id)
    toast.success('已删除')
    emit('delete')
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  }
}
</script>

<style scoped lang="scss">
.password-row {
  display: flex;
  gap: 8px;
  width: 100%;
}
.password-row .el-input {
  flex: 1;
}
.form-actions {
  display: flex;
  gap: 8px;
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid #e5e5ea;
}
</style>
