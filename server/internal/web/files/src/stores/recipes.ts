import { defineStore } from 'pinia'
import { ref } from 'vue'
import { recipeApi } from '@/api/recipes'
import type { Recipe, RecipeInput } from '@/types/recipe'
import { ApiError, ErrorCode } from '@/types/api'

export const useRecipesStore = defineStore('recipes', () => {
  const list = ref<Recipe[]>([])
  const current = ref<Recipe | null>(null)
  const loading = ref(false)

  async function fetchList() {
    loading.value = true
    try {
      list.value = await recipeApi.list()
    } finally {
      loading.value = false
    }
  }

  async function fetchOne(id: string) {
    loading.value = true
    try {
      current.value = await recipeApi.get(id)
    } finally {
      loading.value = false
    }
  }

  async function create(input: RecipeInput): Promise<string> {
    const data = await recipeApi.create(input)
    return data.id
  }

  async function update(id: string, input: RecipeInput) {
    await recipeApi.update(id, input)
  }

  async function remove(id: string) {
    await recipeApi.remove(id)
  }

  function clearCurrent() {
    current.value = null
  }

  return { list, current, loading, fetchList, fetchOne, create, update, remove, clearCurrent }
})

// 错误码映射供视图层使用
export function recipeErrorMsg(err: unknown): string {
  if (err instanceof ApiError) {
    switch (err.code) {
      case ErrorCode.HEADER_MISSING: return '请先配置 Device ID'
      case ErrorCode.TOKEN_INVALID: return 'Sync Token 与服务端不一致'
      case ErrorCode.NO_BACKUP: return '菜谱不存在'
      case ErrorCode.STORE_FAILED: return '保存失败：' + err.message
      case ErrorCode.SYNC_IN_PROGRESS: return '操作进行中，请稍后重试'
      default: return err.message
    }
  }
  return String(err)
}
