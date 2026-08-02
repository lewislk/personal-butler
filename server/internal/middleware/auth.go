package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/lewis/personal-butler/internal/dto"
)

// 与 iOS 客户端契约（AGENTS.md §8）：
// 1001 头缺失 / 1002 密钥错 / 1003 JSON 解析失败
// 2001 存储失败 / 2002 无备份 / 2003 同一设备的写请求正在进行中
// 5000 内部异常
//
// v6 起：移除 X-Device-ID 校验（单用户单设备场景，多设备隔离不再需要）。
// 错误码 1001 仍保留语义为 "missing X-Sync-Token"，但实际只在 token 缺失
// 且服务端配置了 token 时才会触发；token 未配置时跳过校验，便于本地开发。
const (
	CodeOK             = 0
	CodeHeaderMissing  = 1001
	CodeTokenInvalid   = 1002
	CodeJSONParseError = 1003
	CodeStoreFailed    = 2001
	CodeNoBackup       = 2002
	CodeSyncInProgress = 2003
	CodeInternal       = 5000
)

const (
	HeaderSyncToken = "X-Sync-Token"
)

// AuthHeader 校验 X-Sync-Token（v6 起不再校验 X-Device-ID）。
//   - 若服务端 token 配置为空，跳过 token 校验（开发兜底，会打 warn 日志）
//   - 若服务端 token 非空且请求头不匹配，返回 1002
func AuthHeader(expectedToken string) gin.HandlerFunc {
	return func(c *gin.Context) {
		token := c.GetHeader(HeaderSyncToken)
		if expectedToken != "" && token != expectedToken {
			c.AbortWithStatusJSON(http.StatusOK, dto.APIResponse{
				Code: CodeTokenInvalid,
				Msg:  "invalid X-Sync-Token",
			})
			return
		}
		c.Next()
	}
}
