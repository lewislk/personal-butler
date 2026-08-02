import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

const LS_KEY = 'pb_web_cfg'

interface Cfg {
  syncToken: string
}

function loadFromLS(): Cfg {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      // 兼容老版本 LS 里残留的 deviceId 字段：只读取 syncToken
      return { syncToken: parsed.syncToken ?? '' }
    }
  } catch {
    /* ignore */
  }
  return { syncToken: '' }
}

export const useConfigStore = defineStore('config', () => {
  const initial = loadFromLS()
  const syncToken = ref(initial.syncToken)

  // v6 起单用户单设备，仅靠 Sync Token 鉴权
  const isConfigured = computed(() => !!syncToken.value)

  function save() {
    localStorage.setItem(LS_KEY, JSON.stringify({ syncToken: syncToken.value }))
  }

  function clear() {
    syncToken.value = ''
    localStorage.removeItem(LS_KEY)
  }

  return { syncToken, isConfigured, save, clear }
})
