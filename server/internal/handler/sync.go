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

// RegisterDeviceList 挂载 GET /devices 到指定 group。
// 该 group 不应挂任何鉴权 middleware：用户首次配置时既无 device id 也无 token。
func (h *SyncHandler) RegisterDeviceList(rg *gin.RouterGroup) {
	rg.GET("/devices", h.ListDevices)
}

// ListDevices 返回 sync_meta 表中所有 device 列表，供 Web 配置页下拉选择。
func (h *SyncHandler) ListDevices(c *gin.Context) {
	items, err := h.svc.ListDevices()
	if err != nil {
		log.Printf("[sync] list devices failed err=%v", err)
		respond(c, middleware.CodeInternal, "list devices failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", items)
}

// Upload 全量上传：body 是完整 SyncPayload JSON。
func (h *SyncHandler) Upload(c *gin.Context) {
	deviceID := middleware.DeviceID(c)

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

	// 若客户端在 meta 里带了 deviceId 且与 header 不一致，以 header 为准
	if payload.SyncMeta.DeviceID == "" {
		payload.SyncMeta.DeviceID = deviceID
	}

	if err := h.svc.Upload(deviceID, &payload); err != nil {
		if errors.Is(err, service.ErrSyncInProgress) {
			respond(c, middleware.CodeSyncInProgress, "sync in progress, please retry later", nil)
			return
		}
		log.Printf("[sync] upload store failed device=%s err=%v", deviceID, err)
		respond(c, middleware.CodeStoreFailed, "store failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", nil)
}

// Download 返回 SyncPayload 全量。
func (h *SyncHandler) Download(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	payload, err := h.svc.Download(deviceID)
	if err != nil {
		if errors.Is(err, service.ErrNoBackup) {
			respond(c, middleware.CodeNoBackup, "no backup for this device", nil)
			return
		}
		log.Printf("[sync] download failed device=%s err=%v", deviceID, err)
		respond(c, middleware.CodeInternal, "download failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", payload)
}

// Info 返回该 device 备份摘要。
func (h *SyncHandler) Info(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	info, err := h.svc.Info(deviceID)
	if err != nil {
		if errors.Is(err, service.ErrNoBackup) {
			respond(c, middleware.CodeNoBackup, "no backup for this device", nil)
			return
		}
		respond(c, middleware.CodeInternal, "info failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", info)
}

// Clear 清空该 device 全部数据。
func (h *SyncHandler) Clear(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	if err := h.svc.Clear(deviceID); err != nil {
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
