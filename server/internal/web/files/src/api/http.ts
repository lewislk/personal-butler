import axios, { AxiosError, type AxiosInstance, type InternalAxiosRequestConfig } from 'axios'
import { APIResponse, ApiError, ErrorCode } from '@/types/api'
import { useConfigStore } from '@/stores/config'

export const http: AxiosInstance = axios.create({
  baseURL: '',
  timeout: 15000,
})

http.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const cfg = useConfigStore()
  if (!cfg.deviceId) {
    return Promise.reject(new ApiError(ErrorCode.HEADER_MISSING, '请先在配置中填写 Device ID'))
  }
  config.headers.set('X-Device-ID', cfg.deviceId)
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
