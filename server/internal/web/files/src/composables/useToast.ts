import { ElMessage, ElMessageBox } from 'element-plus'
import { ApiError, ErrorCode } from '@/types/api'

// 统一把 ApiError 转中文消息显示
export function useToast() {
  function showError(err: unknown, prefix = '') {
    let msg: string
    if (err instanceof ApiError) {
      switch (err.code) {
        case ErrorCode.HEADER_MISSING: msg = '请先配置 Device ID'; break
        case ErrorCode.TOKEN_INVALID: msg = 'Sync Token 与服务端不一致，请检查配置'; break
        case ErrorCode.NO_BACKUP: msg = '尚无备份数据'; break
        case ErrorCode.SYNC_IN_PROGRESS: msg = '操作进行中，请稍后重试'; break
        case ErrorCode.INTERNAL: msg = '服务异常，请稍后重试'; break
        default: msg = err.message
      }
    } else {
      msg = String(err)
    }
    ElMessage.error(prefix ? `${prefix}：${msg}` : msg)
  }

  function success(msg: string) {
    ElMessage.success(msg)
  }

  function warn(msg: string) {
    ElMessage.warning(msg)
  }

  async function confirm(content: string, title = '确认操作'): Promise<boolean> {
    try {
      await ElMessageBox.confirm(content, title, { type: 'warning' })
      return true
    } catch {
      return false
    }
  }

  return { showError, success, warn, confirm }
}
