import { defineStore } from 'pinia'
import { ref } from 'vue'
import { passwordApi } from '@/api/passwords'
import type { Password, PasswordInput } from '@/types/password'
import { ApiError, ErrorCode } from '@/types/api'

export const usePasswordsStore = defineStore('passwords', () => {
  const list = ref<Password[]>([])
  const current = ref<Password | null>(null)
  const loading = ref(false)

  async function fetchList() {
    loading.value = true
    try {
      list.value = await passwordApi.list()
    } finally {
      loading.value = false
    }
  }

  async function fetchOne(id: string) {
    loading.value = true
    try {
      current.value = await passwordApi.get(id)
    } finally {
      loading.value = false
    }
  }

  async function create(input: PasswordInput): Promise<string> {
    const data = await passwordApi.create(input)
    return data.id
  }

  async function update(id: string, input: PasswordInput) {
    await passwordApi.update(id, input)
  }

  async function remove(id: string) {
    await passwordApi.remove(id)
  }

  function clearCurrent() {
    current.value = null
  }

  return { list, current, loading, fetchList, fetchOne, create, update, remove, clearCurrent }
})

export function passwordErrorMsg(err: unknown): string {
  if (err instanceof ApiError) {
    switch (err.code) {
      case ErrorCode.HEADER_MISSING: return '请先配置 Device ID'
      case ErrorCode.TOKEN_INVALID: return 'Sync Token 与服务端不一致'
      case ErrorCode.NO_BACKUP: return '密码记录不存在'
      case ErrorCode.STORE_FAILED: return '保存失败：' + err.message
      case ErrorCode.SYNC_IN_PROGRESS: return '操作进行中，请稍后重试'
      default: return err.message
    }
  }
  return String(err)
}
