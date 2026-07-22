package config

import (
	"os"
	"strconv"
)

// Config 服务端启动配置：全部通过环境变量读取，未配置则用默认值。
type Config struct {
	// Port HTTP 监听端口，默认 8090（与 iOS 客户端硬编码保持一致）。
	Port int
	// SyncToken 与客户端 X-Sync-Token 请求头比对；空字符串表示不校验（不推荐）。
	SyncToken string

	MySQLDSN string
}

func Load() Config {
	return Config{
		Port:      envInt("PORT", 8090),
		SyncToken: os.Getenv("SYNC_TOKEN"),
		MySQLDSN: envDefault("MYSQL_DSN",
			"root:mysql123@tcp(devbox:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local"),
	}
}

func envDefault(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envInt(k string, def int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
