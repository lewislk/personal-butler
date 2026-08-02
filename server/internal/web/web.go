package web

import (
	"embed"
	"io/fs"
	"net/http"

	"github.com/gin-gonic/gin"
)

//go:embed all:files/dist
var distFS embed.FS

//go:embed files/dist/index.html
var indexHTML []byte

// Register 把 /web 下挂载的静态资源（HTML/CSS/JS）暴露出来。
//
// 设计选择：
//   - 用 embed.FS 把 web/files/dist/* 打进二进制，部署时只有一个可执行文件，零外部依赖。
//   - /web 直接返回 index.html；其它静态资源（JS/CSS）走 /web/static/*。
//   - 前端用 hash 路由（/web#/recipes），无需 Go 端 fallback。
//   - 不复用 /sync/* 路由的 AuthHeader middleware —— 页面本身是 HTML，鉴权信息由前端
//     在 localStorage 维护，每次调 /api/* 时通过 fetch header 带上 X-Sync-Token。
//
// 注意：files/dist/ 是 Vite 构建产物，不入 git。本地开发需先 `cd internal/web/files && npm run build`。
func Register(r *gin.Engine) {
	sub, err := fs.Sub(distFS, "files/dist")
	if err != nil {
		// 仅在 //go:embed 指令写错时才会触发；编译期已保证 dist 目录存在
		panic("web embed: " + err.Error())
	}

	// / → /web（根路径自动跳转，方便用户直接访问 host:8090）
	r.GET("/", func(c *gin.Context) {
		c.Redirect(http.StatusFound, "/web")
	})

	// /web → index.html
	r.GET("/web", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", indexHTML)
	})
	// /web/static/* → JS/CSS/图片
	r.StaticFS("/web/static", http.FS(sub))
}
