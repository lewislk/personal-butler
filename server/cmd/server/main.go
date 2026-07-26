package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lewis/personal-butler/internal/config"
	"github.com/lewis/personal-butler/internal/db"
	"github.com/lewis/personal-butler/internal/handler"
	"github.com/lewis/personal-butler/internal/middleware"
	"github.com/lewis/personal-butler/internal/service"
	"github.com/lewis/personal-butler/internal/web"
)

func main() {
	cfg := config.Load()

	gdb, err := db.Open(cfg.MySQLDSN)
	if err != nil {
		log.Fatalf("db open failed: %v", err)
	}

	// 说明：本项目采用手工维护的 sql/init.sql 建表；不启用 gorm AutoMigrate，避免
	// 生产环境上被静默改结构。若要新增字段，先改 sql/init.sql 并递增 dataVersion。

	svc := service.NewSyncService(gdb)
	syncH := handler.NewSyncHandler(svc)

	// Web 表单录入用的 recipe CRUD service（共享同一个 DB）
	recipeSvc := service.NewRecipeService(gdb)
	recipeH := handler.NewRecipeHandler(recipeSvc)

	if cfg.SyncToken == "" {
		log.Println("[warn] SYNC_TOKEN 未配置，将跳过 X-Sync-Token 校验（仅建议在开发环境这样做）")
	}

	r := gin.New()
	r.Use(gin.Recovery(), gin.Logger())

	// 健康检查（不走鉴权，便于 curl）
	r.GET("/healthz", func(c *gin.Context) { c.String(http.StatusOK, "ok") })

	// Web 表单页面（HTML/JS/CSS 通过 embed.FS 嵌入二进制；不走鉴权）
	web.Register(r)

	// /sync/* 局域网同步（iOS 客户端）
	sync := r.Group("/sync", middleware.AuthHeader(cfg.SyncToken))
	syncH.Register(sync)

	// /api/* Web 表单 CRUD（与 /sync/* 共享同一套鉴权头）
	api := r.Group("/api", middleware.AuthHeader(cfg.SyncToken))
	recipeH.Register(api)

	server := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Port),
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("[server] listening on :%d", cfg.Port)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server error: %v", err)
		}
	}()

	// 优雅退出
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	log.Println("[server] shutting down …")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		log.Printf("shutdown error: %v", err)
	}
}
