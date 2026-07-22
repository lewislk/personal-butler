package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/lewis/personal-butler/internal/dto"
)

// 与 iOS 客户端契约（CLAUDE.md §8）：
// 1001 头缺失 / 1002 密钥错 / 1003 JSON 解析失败
// 2001 存储失败 / 2002 无备份 / 2003 同一设备的写请求正在进行中
// 5000 内部异常
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
	HeaderDeviceID  = "X-Device-ID"
	HeaderSyncToken = "X-Sync-Token"
	CtxDeviceID     = "device_id"
)

// AuthHeader 校验 X-Device-ID 与 X-Sync-Token：
// - device 头缺失 → 1001
// - token 不匹配 → 1002（若服务端 token 配置为空，则跳过 token 校验）
func AuthHeader(expectedToken string) gin.HandlerFunc {
	return func(c *gin.Context) {
		deviceID := c.GetHeader(HeaderDeviceID)
		token := c.GetHeader(HeaderSyncToken)
		if deviceID == "" {
			c.AbortWithStatusJSON(http.StatusOK, dto.APIResponse{
				Code: CodeHeaderMissing,
				Msg:  "missing X-Device-ID",
			})
			return
		}
		if expectedToken != "" && token != expectedToken {
			c.AbortWithStatusJSON(http.StatusOK, dto.APIResponse{
				Code: CodeTokenInvalid,
				Msg:  "invalid X-Sync-Token",
			})
			return
		}
		c.Set(CtxDeviceID, deviceID)
		c.Next()
	}
}

// DeviceID 从 gin.Context 取当前请求的 device 标识。
func DeviceID(c *gin.Context) string {
	if v, ok := c.Get(CtxDeviceID); ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}
