import { http } from './http'
import type { Password, PasswordInput } from '@/types/password'

export const passwordApi = {
  list: () => http.get<Password[]>('/api/passwords'),
  get: (id: string) => http.get<Password>(`/api/passwords/${encodeURIComponent(id)}`),
  create: (input: PasswordInput) => http.post<{ id: string }>('/api/passwords', input),
  update: (id: string, input: PasswordInput) =>
    http.put<void>(`/api/passwords/${encodeURIComponent(id)}`, input),
  remove: (id: string) => http.delete<void>(`/api/passwords/${encodeURIComponent(id)}`),
}
