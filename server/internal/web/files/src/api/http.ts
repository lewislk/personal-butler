import axios, { AxiosError, type AxiosInstance, type InternalAxiosRequestConfig } from 'axios'
import { APIResponse, ApiError, ErrorCode } from '@/types/api'
import { useConfigStore } from '@/stores/config'

export const http: AxiosInstance = axios.create({
  baseURL: '',
  timeout: 15000,
})

http.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const cfg = useConfigStore()
  // /api/devices 是元信息查询，用户首次配置时还没有 device id，也不需要 sync_token
  const isDeviceListUrl = config.url === '/api/devices' || config.url?.startsWith('/api/devices')
  if (!cfg.deviceId && !isDeviceListUrl) {
    return Promise.reject(new ApiError(ErrorCode.HEADER_MISSING, '请先在配置中填写 Device ID'))
  }
  if (cfg.deviceId) {
    config.headers.set('X-Device-ID', cfg.deviceId)
  }
  // 其余端点仍需要 X-Sync-Token；/api/devices 后端已不校验，发送了也无副作用
  config.headers.set('X-Sync-Token', cfg.syncToken || '')
  config.headers.set('Content-Type', 'application/json')
  return config
})

http.interceptors.response.use(
  (resp) => {
    const body = resp.data as APIResponse<unknown>
    if (body.code !== ErrorCode.OK) {
      throw new ApiError(body.code, body.msg || `code=${body.code}`)
    }
    return body.data as any
  },
  (err) => {
    if (err instanceof AxiosError) {
      throw new ApiError(-1, err.message || '网络错误')
    }
    throw err
  }
)

declare module 'axios' {
  export interface AxiosInstance {
    get<T = unknown>(url: string, config?: InternalAxiosRequestConfig): Promise<T>
    post<T = unknown>(url: string, data?: unknown, config?: InternalAxiosRequestConfig): Promise<T>
    put<T = unknown>(url: string, data?: unknown, config?: InternalAxiosRequestConfig): Promise<T>
    delete<T = unknown>(url: string, config?: InternalAxiosRequestConfig): Promise<T>
  }
}
