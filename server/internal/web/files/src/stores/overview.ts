import { defineStore } from 'pinia'
import { ref } from 'vue'
import { syncApi } from '@/api/sync'
import { useRecipesStore } from './recipes'
import { usePasswordsStore } from './passwords'
import type { SyncInfo } from '@/types/api'

export const useOverviewStore = defineStore('overview', () => {
  const info = ref<SyncInfo | null>(null)
  const recipeCount = ref(0)
  const passwordCount = ref(0)
  const loading = ref(false)
  const error = ref('')

  // 并行 fetch 三个数据源，任一失败不影响其他
  async function refresh() {
    loading.value = true
    error.value = ''
    const recipes = useRecipesStore()
    const passwords = usePasswordsStore()

    const tasks: Array<Promise<void>> = [
      (async () => {
        try {
          info.value = await syncApi.getInfo()
        } catch (e) {
          // 首页显示「尚未同步」即可，不抛
          info.value = null
        }
      })(),
      (async () => {
        try {
          await recipes.fetchList()
          recipeCount.value = recipes.list.length
        } catch (e) {
          recipeCount.value = 0
        }
      })(),
      (async () => {
        try {
          await passwords.fetchList()
          passwordCount.value = passwords.list.length
        } catch (e) {
          passwordCount.value = 0
        }
      })(),
    ]
    await Promise.allSettled(tasks)
    loading.value = false
  }

  return { info, recipeCount, passwordCount, loading, error, refresh }
})
