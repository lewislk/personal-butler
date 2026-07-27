import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

const LS_KEY = 'pb_web_cfg'

interface Cfg {
  deviceId: string
  syncToken: string
}

function loadFromLS(): Cfg {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (raw) return JSON.parse(raw)
  } catch {
    /* ignore */
  }
  return { deviceId: '', syncToken: '' }
}

export const useConfigStore = defineStore('config', () => {
  const initial = loadFromLS()
  const deviceId = ref(initial.deviceId)
  const syncToken = ref(initial.syncToken)

  const isConfigured = computed(() => !!deviceId.value)

  function save() {
    localStorage.setItem(LS_KEY, JSON.stringify({ deviceId: deviceId.value, syncToken: syncToken.value }))
  }

  function clear() {
    deviceId.value = ''
    syncToken.value = ''
    localStorage.removeItem(LS_KEY)
  }

  return { deviceId, syncToken, isConfigured, save, clear }
})
