package web

import (
	"embed"
	"io/fs"
	"net/http"

	"github.com/gin-gonic/gin"
)

//go:embed all:files
var filesFS embed.FS

//go:embed files/index.html
var indexHTML []byte

// Register 把 /web 下挂载的静态资源（HTML/CSS/JS）暴露出来。
//
// 设计选择：
//   - 用 embed.FS 把 web/files/* 打进二进制，部署时只有一个可执行文件，零外部依赖。
//   - /web 直接返回 index.html；其它静态资源（app.js / style.css / 图标）走 /web/static/*。
//   - 不复用 /sync/* 路由的 AuthHeader middleware —— 页面本身是 HTML，鉴权信息由前端
//     在 localStorage 维护，每次调 /api/* 时通过 fetch header 带上 X-Device-ID + X-Sync-Token。
//
// 注意：/web 不能用 c.FileFromFS("index.html", ...) —— 那会走 http.ServeFile 的目录规范化
// 逻辑，返回 301 重定向到 ./（相对路径），浏览器跟随跳到 / 然后 404。
// 用 c.Data 直接写字节流绕过这个坑。
func Register(r *gin.Engine) {
	sub, err := fs.Sub(filesFS, "files")
	if err != nil {
		// 仅在 //go:embed 指令写错时才会触发；编译期已保证 files 目录存在
		panic("web embed: " + err.Error())
	}

	// /web → index.html（直接写字节流，避免 ServeFile 的 301 重定向坑）
	r.GET("/web", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", indexHTML)
	})
	// /web/static/* → 其它静态资源
	r.StaticFS("/web/static", http.FS(sub))
}
