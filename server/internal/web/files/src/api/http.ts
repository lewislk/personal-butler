import axios, { AxiosError, type AxiosInstance, type InternalAxiosRequestConfig } from 'axios'
import { APIResponse, ApiError, ErrorCode } from '@/types/api'

const LS_KEY = 'pb_web_cfg'

interface Cfg {
  deviceId: string
  syncToken: string
}

function loadCfg(): Cfg {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (raw) return JSON.parse(raw)
  } catch {
    /* ignore */
  }
  return { deviceId: '', syncToken: '' }
}

export const http: AxiosInstance = axios.create({
  baseURL: '',
  timeout: 15000,
})

// 请求拦截：注入鉴权头
http.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const cfg = loadCfg()
  if (!cfg.deviceId) {
    return Promise.reject(new ApiError(ErrorCode.HEADER_MISSING, '请先在配置中填写 Device ID'))
  }
  config.headers.set('X-Device-ID', cfg.deviceId)
  config.headers.set('X-Sync-Token', cfg.syncToken || '')
  config.headers.set('Content-Type', 'application/json')
  return config
})

// 响应拦截：拆 APIResponse，code !== 0 转 ApiError
http.interceptors.response.use(
  (resp) => {
    const body = resp.data as APIResponse<unknown>
    if (body.code !== ErrorCode.OK) {
      throw new ApiError(body.code, body.msg || `code=${body.code}`)
    }
    // 让业务层直接拿到 data 字段
    return body.data as any
  },
  (err) => {
    if (err instanceof AxiosError) {
      // 网络错误 / 超时 / 非 JSON
      throw new ApiError(-1, err.message || '网络错误')
    }
    throw err
  }
)

// 重写 axios 类型：响应拦截器返回的是 data 字段而非完整 AxiosResponse
declare module 'axios' {
  export interface AxiosInstance {
    get<T = unknown>(url: string, config?: InternalAxiosRequestConfig): Promise<T>
    post<T = unknown>(url: string, data?: unknown, config?: InternalAxiosRequestConfig): Promise<T>
    put<T = unknown>(url: string, data?: unknown, config?: InternalAxiosRequestConfig): Promise<T>
    delete<T = unknown>(url: string, config?: InternalAxiosRequestConfig): Promise<T>
  }
}
