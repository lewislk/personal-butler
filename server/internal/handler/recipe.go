package handler

import (
	"errors"
	"log"

	"github.com/gin-gonic/gin"
	"github.com/lewis/personal-butler/internal/middleware"
	"github.com/lewis/personal-butler/internal/service"
)

// RecipeHandler 暴露 Web 表单 CRUD 接口。
//
// 与 /sync/* 全量覆盖语义不同：/api/recipes/* 走单条增删改，
// 让 Web 端录入不必每次上传全量数据。
//
// 鉴权：复用 AuthHeader middleware（X-Device-ID + X-Sync-Token）。
type RecipeHandler struct {
	svc *service.RecipeService
}

func NewRecipeHandler(svc *service.RecipeService) *RecipeHandler {
	return &RecipeHandler{svc: svc}
}

// Register 在已挂载 AuthHeader middleware 的 RouterGroup 上注册 /api/recipes/*。
func (h *RecipeHandler) Register(rg *gin.RouterGroup) {
	rg.GET("/recipes", h.List)
	rg.POST("/recipes", h.Create)
	rg.GET("/recipes/:id", h.Get)
	rg.PUT("/recipes/:id", h.Update)
	rg.DELETE("/recipes/:id", h.Delete)
}

// List GET /api/recipes
func (h *RecipeHandler) List(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	out, err := h.svc.List(deviceID)
	if err != nil {
		log.Printf("[recipe] list failed device=%s err=%v", deviceID, err)
		respond(c, middleware.CodeInternal, "list failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", out)
}

// Get GET /api/recipes/:id
func (h *RecipeHandler) Get(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	id := c.Param("id")
	out, err := h.svc.Get(deviceID, id)
	if err != nil {
		if errors.Is(err, service.ErrRecipeNotFound) {
			respond(c, middleware.CodeNoBackup, "recipe not found", nil)
			return
		}
		log.Printf("[recipe] get failed device=%s id=%s err=%v", deviceID, id, err)
		respond(c, middleware.CodeInternal, "get failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", out)
}

// Create POST /api/recipes
//
// Body: service.RecipeInput
// 返回 data: { "id": "<uuid>" }
func (h *RecipeHandler) Create(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	var in service.RecipeInput
	if err := c.ShouldBindJSON(&in); err != nil {
		respond(c, middleware.CodeJSONParseError, "invalid json: "+err.Error(), nil)
		return
	}
	if in.Name == "" {
		respond(c, middleware.CodeJSONParseError, "name is required", nil)
		return
	}
	id, err := h.svc.Create(deviceID, &in)
	if err != nil {
		log.Printf("[recipe] create failed device=%s err=%v", deviceID, err)
		respond(c, middleware.CodeStoreFailed, "create failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", gin.H{"id": id})
}

// Update PUT /api/recipes/:id
//
// Body: service.RecipeInput（id 字段需与 path 一致或为空）
func (h *RecipeHandler) Update(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	id := c.Param("id")
	var in service.RecipeInput
	if err := c.ShouldBindJSON(&in); err != nil {
		respond(c, middleware.CodeJSONParseError, "invalid json: "+err.Error(), nil)
		return
	}
	if in.Name == "" {
		respond(c, middleware.CodeJSONParseError, "name is required", nil)
		return
	}
	if err := h.svc.Update(deviceID, id, &in); err != nil {
		switch {
		case errors.Is(err, service.ErrRecipeNotFound):
			respond(c, middleware.CodeNoBackup, "recipe not found", nil)
			return
		case errors.Is(err, service.ErrRecipeIDMismatch):
			respond(c, middleware.CodeJSONParseError, err.Error(), nil)
			return
		}
		log.Printf("[recipe] update failed device=%s id=%s err=%v", deviceID, id, err)
		respond(c, middleware.CodeStoreFailed, "update failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", nil)
}

// Delete DELETE /api/recipes/:id
func (h *RecipeHandler) Delete(c *gin.Context) {
	deviceID := middleware.DeviceID(c)
	id := c.Param("id")
	if err := h.svc.Delete(deviceID, id); err != nil {
		if errors.Is(err, service.ErrRecipeNotFound) {
			respond(c, middleware.CodeNoBackup, "recipe not found", nil)
			return
		}
		log.Printf("[recipe] delete failed device=%s id=%s err=%v", deviceID, id, err)
		respond(c, middleware.CodeStoreFailed, "delete failed: "+err.Error(), nil)
		return
	}
	respond(c, middleware.CodeOK, "ok", nil)
}
