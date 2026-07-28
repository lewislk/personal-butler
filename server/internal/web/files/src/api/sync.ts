import { http } from './http'
import type { SyncInfo, DeviceItem } from '@/types/api'

export const syncApi = {
  getInfo: () => http.get<SyncInfo>('/sync/info'),
  // 列出 sync_meta 表中所有 device，供配置页下拉选择
  listDevices: () => http.get<DeviceItem[]>('/api/devices'),
}
