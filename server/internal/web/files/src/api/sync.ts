import { http } from './http'
import type { SyncInfo } from '@/types/api'

export const syncApi = {
  getInfo: () => http.get<SyncInfo>('/sync/info'),
}
