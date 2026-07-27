// 与 dto.SyncPasswordDTO 对齐
export interface Password {
  id: string
  platform: string
  account: string
  typeText: string
  category: string  // social / office / finance / custom
  passwordPlain: string
  updatedAt: number
  isDemo?: boolean | null
}

export interface PasswordInput {
  id?: string
  platform: string
  account: string
  passwordPlain: string
  typeText: string
  category: string
}
