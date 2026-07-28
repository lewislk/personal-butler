import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { syncApi } from '@/api/sync'
import type { DeviceItem } from '@/types/api'

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

  // 可选 device 列表，来自 sync_meta 表，供配置页下拉选择
  const devices = ref<DeviceItem[]>([])
  const devicesLoading = ref(false)

  const isConfigured = computed(() => !!deviceId.value)

  function save() {
    localStorage.setItem(LS_KEY, JSON.stringify({ deviceId: deviceId.value, syncToken: syncToken.value }))
  }

  function clear() {
    deviceId.value = ''
    syncToken.value = ''
    localStorage.removeItem(LS_KEY)
  }

  // 拉取已上传过数据的 device 列表；后端 /api/devices 不再要求 sync_token
  async function fetchDevices() {
    devicesLoading.value = true
    try {
      devices.value = await syncApi.listDevices()
    } finally {
      devicesLoading.value = false
    }
  }

  return { deviceId, syncToken, devices, devicesLoading, isConfigured, save, clear, fetchDevices }
})
