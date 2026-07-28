// 与服务端 dto.APIResponse 对齐
export interface APIResponse<T> {
  code: number
  msg: string
  data?: T
}

// 与 middleware/auth.go 错误码对齐
export const ErrorCode = {
  OK: 0,
  HEADER_MISSING: 1001,
  TOKEN_INVALID: 1002,
  JSON_PARSE_ERROR: 1003,
  STORE_FAILED: 2001,
  NO_BACKUP: 2002,
  SYNC_IN_PROGRESS: 2003,
  INTERNAL: 5000,
} as const

// 业务层 catch 后可拿到 code 做差异化处理
export class ApiError extends Error {
  code: number
  constructor(code: number, msg: string) {
    super(msg)
    this.name = 'ApiError'
    this.code = code
  }
}

// /sync/info 返回结构
export interface SyncInfo {
  deviceId: string
  syncTimestamp: number
  appVersion: string
  dataVersion: number
  totalCount: number
}

// /api/devices 列表项
export interface DeviceItem {
  deviceId: string
  syncTimestamp: number
  appVersion: string
  dataVersion: number
  // RFC3339 格式
  updatedAt: string
}
