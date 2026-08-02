package handler

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/lewis/personal-butler/internal/dto"
	"github.com/lewis/personal-butler/internal/middleware"
	"github.com/lewis/personal-butler/internal/service"
)

type SyncHandler struct {
	svc *service.SyncService
}

func NewSyncHandler(svc *service.SyncService) *SyncHandler { return &SyncHandler{svc: svc} }

// Register 挂载 4 个同步端点到 /sync/*。
// 顶层已配好 AuthHeader middleware。
func (h *SyncHandler) Register(rg *gin.RouterGroup) {
	rg.POST("/upload", h.Upload)
	rg.GET("/download", h.Download)
	rg.GET("/info", h.Info)
	rg.DELETE("/clear", h.Clear)
}

// Upload 全量上传：body 是完整 SyncPayload JSON。
func (h *SyncHandler) Upload(c *gin.Context) {
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		respond(c, middleware.CodeInternal, "read body failed", nil)
		return
	}
	var payload dto.SyncPayload
	if err := json.Unmarshal(body, &payload); err != nil {
		respond(c, middleware.CodeJSONParseError, "invalid json: "+err.Error(), nil)
		return
	}

	if err := h.svc.Upload(&payload); err != nil {
		if errors.Is(err, service.ErrSyncInProgress) {
			respond(c, middleware.CodeSyncInProgress, "sync in progress, please retry later", nil)
			return
		}
		log.Printf("[sync] upload store failed err=%v", err)
		respond(c, middleware.CodeStoreFailed, "store failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", nil)
}

// Download 返回 SyncPayload 全量。
func (h *SyncHandler) Download(c *gin.Context) {
	payload, err := h.svc.Download()
	if err != nil {
		if errors.Is(err, service.ErrNoBackup) {
			respond(c, middleware.CodeNoBackup, "no backup yet", nil)
			return
		}
		log.Printf("[sync] download failed err=%v", err)
		respond(c, middleware.CodeInternal, "download failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", payload)
}

// Info 返回备份摘要。
func (h *SyncHandler) Info(c *gin.Context) {
	info, err := h.svc.Info()
	if err != nil {
		if errors.Is(err, service.ErrNoBackup) {
			respond(c, middleware.CodeNoBackup, "no backup yet", nil)
			return
		}
		respond(c, middleware.CodeInternal, "info failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", info)
}

// Clear 清空全部数据。
func (h *SyncHandler) Clear(c *gin.Context) {
	if err := h.svc.Clear(); err != nil {
		if errors.Is(err, service.ErrSyncInProgress) {
			respond(c, middleware.CodeSyncInProgress, "sync in progress, please retry later", nil)
			return
		}
		respond(c, middleware.CodeStoreFailed, "clear failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", nil)
}

func respond(c *gin.Context, code int, msg string, data any) {
	c.JSON(http.StatusOK, dto.APIResponse{Code: code, Msg: msg, Data: data})
}
