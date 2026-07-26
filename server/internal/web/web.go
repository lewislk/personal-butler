package web

import (
	"embed"
	"io/fs"
	"net/http"

	"github.com/gin-gonic/gin"
)

//go:embed all:files
var filesFS embed.FS

// Register 把 /web 下挂载的静态资源（HTML/CSS/JS）暴露出来。
//
// 设计选择：
//   - 用 embed.FS 把 web/files/* 打进二进制，部署时只有一个可执行文件，零外部依赖。
//   - /web 直接返回 index.html；其它静态资源（app.js / style.css / 图标）走 /web/static/*。
//   - 不复用 /sync/* 路由的 AuthHeader middleware —— 页面本身是 HTML，鉴权信息由前端
//     在 localStorage 维护，每次调 /api/* 时通过 fetch header 带上 X-Device-ID + X-Sync-Token。
func Register(r *gin.Engine) {
	sub, err := fs.Sub(filesFS, "files")
	if err != nil {
		// 仅在 //go:embed 指令写错时才会触发；编译期已保证 files 目录存在
		panic("web embed: " + err.Error())
	}

	// /web → index.html
	r.GET("/web", func(c *gin.Context) {
		c.FileFromFS("index.html", http.FS(sub))
	})
	// /web/static/* → 其它静态资源
	r.StaticFS("/web/static", http.FS(sub))
}
