package handler

import (
	"errors"
	"log"

	"github.com/gin-gonic/gin"
	"github.com/lewis/personal-butler/internal/middleware"
	"github.com/lewis/personal-butler/internal/service"
)

// PasswordHandler 暴露 Web 表单密码 CRUD 接口，模式与 RecipeHandler 一致。
type PasswordHandler struct {
	svc *service.PasswordService
}

func NewPasswordHandler(svc *service.PasswordService) *PasswordHandler {
	return &PasswordHandler{svc: svc}
}

// Register 在已挂载 AuthHeader middleware 的 RouterGroup 上注册 /api/passwords/*。
func (h *PasswordHandler) Register(rg *gin.RouterGroup) {
	rg.GET("/passwords", h.List)
	rg.POST("/passwords", h.Create)
	rg.GET("/passwords/:id", h.Get)
	rg.PUT("/passwords/:id", h.Update)
	rg.DELETE("/passwords/:id", h.Delete)
}

func (h *PasswordHandler) List(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	out, err := h.svc.List(deviceID)
	if err != nil {
		log.Printf("[password] list failed device=%s err=%v", deviceID, err)
		respond(c, middleware.CodeInternal, "list failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", out)
}

func (h *PasswordHandler) Get(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	id := c.Param("id")
	out, err := h.svc.Get(deviceID, id)
	if err != nil {
		if errors.Is(err, service.ErrPasswordNotFound) {
			respond(c, middleware.CodeNoBackup, "password not found", nil)
			return
		}
		log.Printf("[password] get failed device=%s id=%s err=%v", deviceID, id, err)
		respond(c, middleware.CodeInternal, "get failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", out)
}

// Create POST /api/passwords
// Body: service.PasswordInput
// 返回 data: { "id": "<uuid>" }
func (h *PasswordHandler) Create(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	var in service.PasswordInput
	if err := c.ShouldBindJSON(&in); err != nil {
		respond(c, middleware.CodeJSONParseError, "invalid json: "+err.Error(), nil)
		return
	}
	if in.Platform == "" {
		respond(c, middleware.CodeJSONParseError, "platform is required", nil)
		return
	}
	if in.Account == "" {
		respond(c, middleware.CodeJSONParseError, "account is required", nil)
		return
	}
	if in.PasswordPlain == "" {
		respond(c, middleware.CodeJSONParseError, "passwordPlain is required", nil)
		return
	}
	id, err := h.svc.Create(deviceID, &in)
	if err != nil {
		log.Printf("[password] create failed device=%s err=%v", deviceID, err)
		respond(c, middleware.CodeStoreFailed, "create failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", gin.H{"id": id})
}

func (h *PasswordHandler) Update(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	id := c.Param("id")
	var in service.PasswordInput
	if err := c.ShouldBindJSON(&in); err != nil {
		respond(c, middleware.CodeJSONParseError, "invalid json: "+err.Error(), nil)
		return
	}
	if in.Platform == "" {
		respond(c, middleware.CodeJSONParseError, "platform is required", nil)
		return
	}
	if in.Account == "" {
		respond(c, middleware.CodeJSONParseError, "account is required", nil)
		return
	}
	if in.PasswordPlain == "" {
		respond(c, middleware.CodeJSONParseError, "passwordPlain is required", nil)
		return
	}
	if err := h.svc.Update(deviceID, id, &in); err != nil {
		switch {
		case errors.Is(err, service.ErrPasswordNotFound):
			respond(c, middleware.CodeNoBackup, "password not found", nil)
			return
		case errors.Is(err, service.ErrPasswordIDMismatch):
			respond(c, middleware.CodeJSONParseError, err.Error(), nil)
			return
		}
		log.Printf("[password] update failed device=%s id=%s err=%v", deviceID, id, err)
		respond(c, middleware.CodeStoreFailed, "update failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", nil)
}

func (h *PasswordHandler) Delete(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	id := c.Param("id")
	if err := h.svc.Delete(deviceID, id); err != nil {
		if errors.Is(err, service.ErrPasswordNotFound) {
			respond(c, middleware.CodeNoBackup, "password not found", nil)
			return
		}
		log.Printf("[password] delete failed device=%s id=%s err=%v", deviceID, id, err)
		respond(c, middleware.CodeStoreFailed, "delete failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", nil)
}
