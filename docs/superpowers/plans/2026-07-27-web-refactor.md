# Web 后台录入重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Vite+Vue3+TS+Element-Plus 重构 server/internal/web，新增后端 Password CRUD，完善烹饪管理与密码记录两个页面的后台录入。

**Architecture:** Hash 路由 SPA，4 个独立 Pinia store，axios 拦截器统一注入鉴权头并拆 APIResponse，Element-Plus 自动按需引入。Vue 构建产物走 Go embed.FS 嵌入二进制，保持「单二进制零依赖」部署模式。后端完全复制 recipe.go 模式新增 Password CRUD。

**Tech Stack:** Vite 5 / Vue 3.4 / TypeScript 5 / vue-router 4 / Pinia 2 / Axios 1 / Element-Plus 2 / SCSS / ESLint + Prettier / Go 1.22 + Gin + GORM

## Global Constraints

- iOS 最低版本 18，纯 SwiftUI（不影响本计划，但保持约定一致）
- 简体中文 UI（`locale: zh-Hans`），代码标识符英文，注释可中文
- 主色 `#007aff`（与 iOS AppColorTheme 对齐）
- 鉴权头：`X-Device-ID` + `X-Sync-Token`，与 `/sync/*` 共用
- 错误码：0/1001/1002/1003/2001/2002/2003/5000（与 middleware/auth.go 一致）
- 图片压缩：JPEG 0.7 + 512px max side（与 iOS ImageProcessor.swift 约定一致）
- Schema v5，dataVersion 不变（password 表已存在，无 schema 变更）
- Web 表单创建的数据 `is_demo=0`（用户自添语义）
- 不写单元测试（MVP 阶段约定）
- Hash 路由（零后端 fallback 改动）
- `dist/` 不进 git，由 Docker 构建期或本地 `npm run build` 生成
- 旧三件套（index.html / app.js / style.css）会被 Vite 工程覆盖删除

**Spec 引用：** [docs/superpowers/specs/2026-07-27-web-refactor-design.md](../specs/2026-07-27-web-refactor-design.md)

---

## 文件结构总览

### 后端新增/修改（3 个文件）
- Create: `server/internal/service/password.go` — PasswordService + PasswordInput
- Create: `server/internal/handler/password.go` — PasswordHandler + 5 个端点
- Modify: `server/cmd/server/main.go` — 注册 passwordH

### 前端工程（~30 个文件，全部位于 `server/internal/web/files/`）
- 配置：`package.json` / `vite.config.ts` / `tsconfig.json` / `tsconfig.node.json` / `.eslintrc.cjs` / `.prettierrc.json` / `index.html` / `.gitignore` / `env.d.ts`
- 入口：`src/main.ts` / `src/App.vue`
- 路由：`src/router/index.ts`
- 类型：`src/types/{api,recipe,password}.ts`
- API：`src/api/{http,recipes,passwords,sync}.ts`
- Store：`src/stores/{config,recipes,passwords,overview}.ts`
- Composable：`src/composables/{useImageCompress,useToast}.ts`
- 视图：`src/views/{HomeView,RecipesView,PasswordsView,SettingsView}.vue`
- 组件：`src/components/{AppHeader,ConfigDrawer,EmptyState,RecipeForm,IngredientEditor,PasswordForm,ImagePicker}.vue`
- 样式：`src/styles/{variables,global}.scss`

### 部署改造（2 个文件）
- Modify: `server/internal/web/web.go` — embed `files/dist/` 而非 `files/`
- Modify: `server/Dockerfile` — 加 Node 构建阶段

### 删除（3 个文件）
- Delete: `server/internal/web/files/{index.html,app.js,style.css}`（旧三件套，被 Vite 工程替代）

---

## Task 1: 后端 Password CRUD

**Files:**
- Create: `server/internal/service/password.go`
- Create: `server/internal/handler/password.go`
- Modify: `server/cmd/server/main.go:38-60`（在 recipeH 注册后追加 passwordH 注册）

**Interfaces:**
- Consumes: `service.newUUID()` / `service.upsertSyncMeta(tx, deviceID)` / `service.currentDataVersion`（来自 recipe.go，同包复用）；`model.Password` / `dto.SyncPasswordDTO`（已存在）；`middleware.DeviceID(c)` / `respond(c, code, msg, data)`（来自 handler 包）
- Produces: `service.NewPasswordService(db)` / `service.PasswordInput` / `service.ErrPasswordNotFound` / `service.ErrPasswordIDMismatch` / `handler.NewPasswordHandler(svc)` / `(*PasswordHandler).Register(rg)`

- [ ] **Step 1: 创建 `server/internal/service/password.go`**

```go
package service

import (
	"errors"
	"time"

	"github.com/lewis/personal-butler/internal/dto"
	"github.com/lewis/personal-butler/internal/model"
	"gorm.io/gorm"
)

// PasswordService 提供 Web 表单录入密码所需的 CRUD 能力。
// 模式与 RecipeService 完全一致：单条增删改，每次写入后 upsert sync_meta。
type PasswordService struct {
	db *gorm.DB
}

func NewPasswordService(db *gorm.DB) *PasswordService { return &PasswordService{db: db} }

var (
	ErrPasswordNotFound   = errors.New("password not found")
	ErrPasswordIDMismatch = errors.New("password id in path does not match body")
)

// PasswordInput 与 Web 表单提交结构对齐。
// ID POST 时留空（服务端生成 UUID）；PUT 时必填且与 path 一致。
// Category 留空时后端兜底为 "social"（与 iOS PasswordCategory 默认值一致）。
type PasswordInput struct {
	ID            *string `json:"id,omitempty"`
	Platform      string  `json:"platform"`
	Account       string  `json:"account"`
	PasswordPlain string  `json:"passwordPlain"`
	TypeText      string  `json:"typeText"`
	Category      string  `json:"category"`
}

// List 返回该 device 下所有密码，按 updatedAt 倒序（与 iOS PasswordView 排序一致）。
func (s *PasswordService) List(deviceID string) ([]dto.SyncPasswordDTO, error) {
	var rows []model.Password
	if err := s.db.Where("device_id = ?", deviceID).Order("updated_at desc").Find(&rows).Error; err != nil {
		return nil, err
	}
	out := make([]dto.SyncPasswordDTO, 0, len(rows))
	for _, p := range rows {
		out = append(out, dto.SyncPasswordDTO{
			ID:            p.ID,
			Platform:      p.Platform,
			Account:       p.Account,
			TypeText:      p.TypeText,
			Category:      p.Category,
			PasswordPlain: p.PasswordPlain,
			UpdatedAt:     p.UpdatedAt,
			IsDemo:        boolPtr(p.IsDemo),
		})
	}
	return out, nil
}

// Get 取单个密码。
func (s *PasswordService) Get(deviceID, id string) (*dto.SyncPasswordDTO, error) {
	var p model.Password
	if err := s.db.Where("device_id = ? AND id = ?", deviceID, id).First(&p).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrPasswordNotFound
		}
		return nil, err
	}
	return &dto.SyncPasswordDTO{
		ID:            p.ID,
		Platform:      p.Platform,
		Account:       p.Account,
		TypeText:      p.TypeText,
		Category:      p.Category,
		PasswordPlain: p.PasswordPlain,
		UpdatedAt:     p.UpdatedAt,
		IsDemo:        boolPtr(p.IsDemo),
	}, nil
}

// Create 新建密码。返回新 id。
func (s *PasswordService) Create(deviceID string, in *PasswordInput) (string, error) {
	id := newUUID()
	category := in.Category
	if category == "" {
		category = "social"
	}
	p := model.Password{
		DeviceID:      deviceID,
		ID:            id,
		Platform:      in.Platform,
		Account:       in.Account,
		TypeText:      in.TypeText,
		Category:      category,
		PasswordPlain: in.PasswordPlain,
		UpdatedAt:     float64(time.Now().Unix()),
	}
	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&p).Error; err != nil {
			return err
		}
		return upsertSyncMeta(tx, deviceID)
	})
	if err != nil {
		return "", err
	}
	return id, nil
}

// Update 全量更新密码字段。
func (s *PasswordService) Update(deviceID, id string, in *PasswordInput) error {
	if in.ID == nil || *in.ID != id {
		return ErrPasswordIDMismatch
	}
	var exists model.Password
	if err := s.db.Where("device_id = ? AND id = ?", deviceID, id).First(&exists).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrPasswordNotFound
		}
		return err
	}
	category := in.Category
	if category == "" {
		category = "social"
	}
	err := s.db.Transaction(func(tx *gorm.DB) error {
		updates := map[string]any{
			"platform":       in.Platform,
			"account":        in.Account,
			"type_text":      in.TypeText,
			"category":       category,
			"password_plain": in.PasswordPlain,
			"updated_at":     float64(time.Now().Unix()),
		}
		if err := tx.Model(&model.Password{}).
			Where("device_id = ? AND id = ?", deviceID, id).
			Updates(updates).Error; err != nil {
			return err
		}
		return upsertSyncMeta(tx, deviceID)
	})
	return err
}

// Delete 删除密码。
func (s *PasswordService) Delete(deviceID, id string) error {
	var exists model.Password
	if err := s.db.Where("device_id = ? AND id = ?", deviceID, id).First(&exists).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrPasswordNotFound
		}
		return err
	}
	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("device_id = ? AND id = ?", deviceID, id).
			Delete(&model.Password{}).Error; err != nil {
			return err
		}
		return upsertSyncMeta(tx, deviceID)
	})
}
```

- [ ] **Step 2: 创建 `server/internal/handler/password.go`**

```go
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
```

- [ ] **Step 3: 修改 `server/cmd/server/main.go`，在 recipeH.Register(api) 后追加**

定位现有代码（第 38-60 行附近）：
```go
	recipeSvc := service.NewRecipeService(gdb)
	recipeH := handler.NewRecipeHandler(recipeSvc)
```
与
```go
	recipeH.Register(api)
```

在对应位置追加 password 注册：

```go
	// Web 表单录入用的 password CRUD service（共享同一个 DB）
	passwordSvc := service.NewPasswordService(gdb)
	passwordH := handler.NewPasswordHandler(passwordSvc)
```

```go
	passwordH.Register(api)
```

- [ ] **Step 4: 编译验证**

Run: `cd server && go build ./cmd/server`
Expected: 编译通过，无错误

- [ ] **Step 5: 启动服务并 curl 自测**

启动（需要本地 MySQL）：
```bash
cd server
SYNC_TOKEN=changeme MYSQL_DSN='root:root@tcp(127.0.0.1:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local' PORT=8090 go run ./cmd/server
```

另开终端跑 curl：
```bash
# 创建
curl -s -X POST http://127.0.0.1:8090/api/passwords \
  -H 'Content-Type: application/json' \
  -H 'X-Device-ID: dev-test' \
  -H 'X-Sync-Token: changeme' \
  --data '{"platform":"GitHub","account":"alice@example.com","passwordPlain":"p@ssw0rd","category":"social","typeText":"社交 · 常用"}'
# 期望：{"code":0,"msg":"ok","data":{"id":"..."}}

# 列表
curl -s http://127.0.0.1:8090/api/passwords -H 'X-Device-ID: dev-test' -H 'X-Sync-Token: changeme'
# 期望：{"code":0,"msg":"ok","data":[{"id":"...","platform":"GitHub",...}]}

# 缺字段
curl -s -X POST http://127.0.0.1:8090/api/passwords \
  -H 'Content-Type: application/json' \
  -H 'X-Device-ID: dev-test' \
  -H 'X-Sync-Token: changeme' \
  --data '{"platform":"","account":"x","passwordPlain":"y"}'
# 期望：{"code":1003,"msg":"platform is required"}
```

- [ ] **Step 6: 提交**

```bash
git add server/internal/service/password.go server/internal/handler/password.go server/cmd/server/main.go
git commit -m "feat(server): add password CRUD endpoints for web form"
```

---

## Task 2: Vue 工程脚手架 + 删除旧三件套

**Files:**
- Delete: `server/internal/web/files/index.html` / `app.js` / `style.css`
- Create: `server/internal/web/files/package.json` / `vite.config.ts` / `tsconfig.json` / `tsconfig.node.json` / `.eslintrc.cjs` / `.prettierrc.json` / `.gitignore` / `index.html` / `src/env.d.ts` / `src/main.ts` / `src/App.vue`

**Interfaces:**
- Consumes: 无（脚手架）
- Produces: 可运行的 Vite dev server（`npm run dev` 启动后浏览器看到 hello world）；`@/` 路径别名指向 `src/`

- [ ] **Step 1: 删除旧三件套**

```bash
rm server/internal/web/files/index.html
rm server/internal/web/files/app.js
rm server/internal/web/files/style.css
```

- [ ] **Step 2: 创建 `server/internal/web/files/.gitignore`**

```
node_modules/
dist/
.DS_Store
*.log
.vite/
```

- [ ] **Step 3: 创建 `server/internal/web/files/package.json`**

```json
{
  "name": "personal-butler-web",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc --noEmit && vite build",
    "preview": "vite preview",
    "lint": "eslint . --ext .vue,.js,.ts,.cjs --fix --ignore-path .gitignore",
    "format": "prettier --write src/"
  },
  "dependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.3.0",
    "pinia": "^2.1.0",
    "axios": "^1.6.0",
    "element-plus": "^2.5.0",
    "@element-plus/icons-vue": "^2.3.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.0.0",
    "vite": "^5.0.0",
    "vue-tsc": "^2.0.0",
    "typescript": "^5.3.0",
    "sass": "^1.70.0",
    "unplugin-vue-components": "^0.26.0",
    "unplugin-auto-import": "^0.17.0",
    "eslint": "^8.56.0",
    "eslint-plugin-vue": "^9.21.0",
    "@typescript-eslint/parser": "^7.0.0",
    "@typescript-eslint/eslint-plugin": "^7.0.0",
    "prettier": "^3.2.0"
  }
}
```

- [ ] **Step 4: 创建 `server/internal/web/files/vite.config.ts`**

```ts
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import Components from 'unplugin-vue-components/vite'
import AutoImport from 'unplugin-auto-import/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import { fileURLToPath, URL } from 'node:url'

// 生产构建输出到 dist/，Go 端 //go:embed all:files/dist 会嵌入
// 开发模式 dev server 端口 5173，API 走 proxy 到本地 Go 服务
export default defineConfig({
  plugins: [
    vue(),
    AutoImport({
      imports: ['vue', 'vue-router', 'pinia'],
      resolvers: [ElementPlusResolver()],
      dts: 'src/auto-imports.d.ts',
    }),
    Components({
      resolvers: [ElementPlusResolver()],
      dts: 'src/components.d.ts',
    }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:8090',
      '/sync': 'http://localhost:8090',
    },
  },
})
```

- [ ] **Step 5: 创建 `server/internal/web/files/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "preserve",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["src/**/*.ts", "src/**/*.d.ts", "src/**/*.tsx", "src/**/*.vue"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

- [ ] **Step 6: 创建 `server/internal/web/files/tsconfig.node.json`**

```json
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts"]
}
```

- [ ] **Step 7: 创建 `server/internal/web/files/.eslintrc.cjs`**

```js
/* eslint-env node */
module.exports = {
  root: true,
  env: { browser: true, node: true, es2021: true },
  extends: [
    'eslint:recommended',
    'plugin:vue/vue3-recommended',
    'plugin:@typescript-eslint/recommended',
  ],
  parser: 'vue-eslint-parser',
  parserOptions: {
    parser: '@typescript-eslint/parser',
    ecmaVersion: 'latest',
    sourceType: 'module',
  },
  rules: {
    'vue/multi-word-component-names': 'off',
    '@typescript-eslint/no-explicit-any': 'warn',
    '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
  },
  ignorePatterns: ['dist/', 'node_modules/', '*.d.ts'],
}
```

- [ ] **Step 8: 创建 `server/internal/web/files/.prettierrc.json`**

```json
{
  "semi": false,
  "singleQuote": true,
  "trailingComma": "es5",
  "printWidth": 100,
  "tabWidth": 2,
  "vueIndentScriptAndStyle": false
}
```

- [ ] **Step 9: 创建 `server/internal/web/files/index.html`**

```html
<!DOCTYPE html>
<html lang="zh-Hans">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
    <title>PersonalButler · 后台录入</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
```

- [ ] **Step 10: 创建 `server/internal/web/files/src/env.d.ts`**

```ts
/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<{}, {}, any>
  export default component
}
```

- [ ] **Step 11: 创建 `server/internal/web/files/src/styles/variables.scss`**

```scss
// 覆盖 Element-Plus 主题变量，与 iOS AppColorTheme 主色 #007aff 对齐
// 必须在 element-plus/scss/index 之前导入
$colors: (
  'primary': (
    'base': #007aff,
  ),
);

// 圆角与 iOS 端约定一致（12/8/6）
$border-radius: (
  'base': 8px,
  'small': 6px,
  'round': 12px,
);
```

- [ ] **Step 12: 创建 `server/internal/web/files/src/styles/global.scss`**

```scss
* {
  box-sizing: border-box;
}
html,
body {
  margin: 0;
  padding: 0;
}
body {
  font-family: -apple-system, 'Helvetica Neue', 'PingFang SC', 'Microsoft YaHei', sans-serif;
  background: #f6f7f9;
  color: #1c1c1e;
  font-size: 14px;
  line-height: 1.5;
  min-height: 100vh;
}
#app {
  min-height: 100vh;
}
```

- [ ] **Step 13: 创建 `server/internal/web/files/src/App.vue`（最小占位版，Task 5 会扩展）**

```vue
<template>
  <div class="app-placeholder">
    <h1>PersonalButler Web</h1>
    <p>脚手架就绪，等待 Task 5 接入路由</p>
  </div>
</template>

<script setup lang="ts"></script>

<style scoped>
.app-placeholder {
  padding: 48px;
  text-align: center;
}
</style>
```

- [ ] **Step 14: 创建 `server/internal/web/files/src/main.ts`**

```ts
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import './styles/global.scss'

const app = createApp(App)
app.use(createPinia())
app.mount('#app')
```

- [ ] **Step 15: 安装依赖并启动 dev server 验证**

```bash
cd server/internal/web/files
npm install --registry=https://registry.npmmirror.com
npm run dev
```

打开浏览器访问 `http://localhost:5173`，应看到「PersonalButler Web / 脚手架就绪」。
按 Ctrl+C 停止。

- [ ] **Step 16: 构建验证（dist 必须能生成，后续 Go embed 依赖）**

```bash
cd server/internal/web/files
npm run build
ls -la dist/
```

预期 `dist/` 下有 `index.html` / `assets/` 目录。

- [ ] **Step 17: 提交**

```bash
git add server/internal/web/files/
git rm server/internal/web/files/index.html server/internal/web/files/app.js server/internal/web/files/style.css  # 如果还没删
git commit -m "feat(web): scaffold Vite+Vue3+TS project, remove legacy HTML/JS/CSS"
```

注意：`dist/` 和 `node_modules/` 已在 `.gitignore` 中排除，不会进 git。

---

## Task 3: 类型定义 + API 层

**Files:**
- Create: `server/internal/web/files/src/types/api.ts` / `recipe.ts` / `password.ts`
- Create: `server/internal/web/files/src/api/http.ts` / `recipes.ts` / `passwords.ts` / `sync.ts`

**Interfaces:**
- Consumes: Task 2 的 axios（已装）+ Pinia（已装，但 config store 在 Task 4 实现，本任务先用占位读取 localStorage）
- Produces:
  - `types/api.ts`: `APIResponse<T>` / `ApiError` / `ErrorCode` 常量
  - `types/recipe.ts`: `Recipe` / `RecipeIngredient` / `RecipeInput`
  - `types/password.ts`: `Password` / `PasswordInput`
  - `api/http.ts`: `http` axios 实例（导出 default）
  - `api/recipes.ts`: `recipeApi` 对象
  - `api/passwords.ts`: `passwordApi` 对象
  - `api/sync.ts`: `syncApi.getInfo()`

- [ ] **Step 1: 创建 `src/types/api.ts`**

```ts
// 与服务端 dto.APIResponse 对齐
export interface APIResponse<T> {
  code: number
  msg: string
  data?: T
}

// 与 middleware/auth.go 错误码对齐
export const ErrorCode = {
  OK: 0,
  HEADER_MISSING: 1001,
  TOKEN_INVALID: 1002,
  JSON_PARSE_ERROR: 1003,
  STORE_FAILED: 2001,
  NO_BACKUP: 2002,
  SYNC_IN_PROGRESS: 2003,
  INTERNAL: 5000,
} as const

// 业务层 catch 后可拿到 code 做差异化处理
export class ApiError extends Error {
  code: number
  constructor(code: number, msg: string) {
    super(msg)
    this.name = 'ApiError'
    this.code = code
  }
}

// /sync/info 返回结构
export interface SyncInfo {
  deviceId: string
  syncTimestamp: number
  appVersion: string
  dataVersion: number
  totalCount: number
}
```

- [ ] **Step 2: 创建 `src/types/recipe.ts`**

```ts
// 与 dto.SyncRecipeDTO / SyncIngredientDTO 对齐
export interface RecipeIngredient {
  id: string
  name: string
  amount: string
  order: number
}

export interface Recipe {
  id: string
  name: string
  emoji: string
  difficulty: string  // easy / medium / hard
  minutes: number
  category: string    // home / noodle / soup / dessert
  ingredientsLegacyRaw: string
  ingredients: RecipeIngredient[]
  steps: string
  tips: string
  iconImageBase64?: string | null
  isDemo?: boolean | null
}

// POST/PUT 提交结构。id 创建时省略，编辑时必填
export interface RecipeInput {
  id?: string
  name: string
  emoji: string
  difficulty: string
  minutes: number
  category: string
  steps: string
  tips: string
  ingredientsLegacyRaw: string
  iconImageBase64?: string | null
  ingredients: Array<{
    id?: string
    name: string
    amount: string
    order: number
  }>
}
```

- [ ] **Step 3: 创建 `src/types/password.ts`**

```ts
// 与 dto.SyncPasswordDTO 对齐
export interface Password {
  id: string
  platform: string
  account: string
  typeText: string
  category: string  // social / office / finance / custom
  passwordPlain: string
  updatedAt: number
  isDemo?: boolean | null
}

export interface PasswordInput {
  id?: string
  platform: string
  account: string
  passwordPlain: string
  typeText: string
  category: string
}
```

- [ ] **Step 4: 创建 `src/api/http.ts`**

注意：Task 4 才创建 config store，本任务先用 localStorage 直读，Task 4 完成后改用 store。这样可以让 API 层先可独立验证。

```ts
import axios, { AxiosError, type AxiosInstance, type InternalAxiosRequestConfig } from 'axios'
import { APIResponse, ApiError, ErrorCode } from '@/types/api'

const LS_KEY = 'pb_web_cfg'

interface Cfg {
  deviceId: string
  syncToken: string
}

function loadCfg(): Cfg {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (raw) return JSON.parse(raw)
  } catch {
    /* ignore */
  }
  return { deviceId: '', syncToken: '' }
}

export const http: AxiosInstance = axios.create({
  baseURL: '',
  timeout: 15000,
})

// 请求拦截：注入鉴权头
http.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const cfg = loadCfg()
  if (!cfg.deviceId) {
    return Promise.reject(new ApiError(ErrorCode.HEADER_MISSING, '请先在配置中填写 Device ID'))
  }
  config.headers.set('X-Device-ID', cfg.deviceId)
  config.headers.set('X-Sync-Token', cfg.syncToken || '')
  config.headers.set('Content-Type', 'application/json')
  return config
})

// 响应拦截：拆 APIResponse，code !== 0 转 ApiError
http.interceptors.response.use(
  (resp) => {
    const body = resp.data as APIResponse<unknown>
    if (body.code !== ErrorCode.OK) {
      throw new ApiError(body.code, body.msg || `code=${body.code}`)
    }
    // 让业务层直接拿到 data 字段
    return body.data as any
  },
  (err) => {
    if (err instanceof AxiosError) {
      // 网络错误 / 超时 / 非 JSON
      throw new ApiError(-1, err.message || '网络错误')
    }
    throw err
  }
)

// 重写 axios 类型：响应拦截器返回的是 data 字段而非完整 AxiosResponse
declare module 'axios' {
  export interface AxiosInstance {
    get<T = unknown>(url: string, config?: InternalAxiosRequestConfig): Promise<T>
    post<T = unknown>(url: string, data?: unknown, config?: InternalAxiosRequestConfig): Promise<T>
    put<T = unknown>(url: string, data?: unknown, config?: InternalAxiosRequestConfig): Promise<T>
    delete<T = unknown>(url: string, config?: InternalAxiosRequestConfig): Promise<T>
  }
}
```

- [ ] **Step 5: 创建 `src/api/recipes.ts`**

```ts
import { http } from './http'
import type { Recipe, RecipeInput } from '@/types/recipe'

export const recipeApi = {
  list: () => http.get<Recipe[]>('/api/recipes'),
  get: (id: string) => http.get<Recipe>(`/api/recipes/${encodeURIComponent(id)}`),
  create: (input: RecipeInput) => http.post<{ id: string }>('/api/recipes', input),
  update: (id: string, input: RecipeInput) =>
    http.put<void>(`/api/recipes/${encodeURIComponent(id)}`, input),
  remove: (id: string) => http.delete<void>(`/api/recipes/${encodeURIComponent(id)}`),
}
```

- [ ] **Step 6: 创建 `src/api/passwords.ts`**

```ts
import { http } from './http'
import type { Password, PasswordInput } from '@/types/password'

export const passwordApi = {
  list: () => http.get<Password[]>('/api/passwords'),
  get: (id: string) => http.get<Password>(`/api/passwords/${encodeURIComponent(id)}`),
  create: (input: PasswordInput) => http.post<{ id: string }>('/api/passwords', input),
  update: (id: string, input: PasswordInput) =>
    http.put<void>(`/api/passwords/${encodeURIComponent(id)}`, input),
  remove: (id: string) => http.delete<void>(`/api/passwords/${encodeURIComponent(id)}`),
}
```

- [ ] **Step 7: 创建 `src/api/sync.ts`**

```ts
import { http } from './http'
import type { SyncInfo } from '@/types/api'

export const syncApi = {
  getInfo: () => http.get<SyncInfo>('/sync/info'),
}
```

- [ ] **Step 8: 类型检查**

```bash
cd server/internal/web/files
npx vue-tsc --noEmit
```

Expected: 无类型错误（auto-imports.d.ts 和 components.d.ts 由 vite 插件在 dev/build 时生成，vue-tsc 首次跑可能报缺文件警告，可先 `npm run dev` 启动一次让其生成，再停止）。

- [ ] **Step 9: 提交**

```bash
git add server/internal/web/files/src/
git commit -m "feat(web): add type definitions and API layer with axios interceptors"
```

---

## Task 4: Pinia stores

**Files:**
- Create: `server/internal/web/files/src/stores/config.ts` / `recipes.ts` / `passwords.ts` / `overview.ts`
- Modify: `server/internal/web/files/src/api/http.ts`（改用 config store 替代直读 localStorage）

**Interfaces:**
- Consumes: Task 3 的 API 层 + types
- Produces:
  - `useConfigStore()`：deviceId / syncToken / isConfigured / save() / clear()
  - `useRecipesStore()`：list / current / loading / fetchList() / fetchOne() / create() / update() / remove()
  - `usePasswordsStore()`：同上
  - `useOverviewStore()`：info / recipeCount / passwordCount / refresh()

- [ ] **Step 1: 创建 `src/stores/config.ts`**

```ts
import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

const LS_KEY = 'pb_web_cfg'

interface Cfg {
  deviceId: string
  syncToken: string
}

function loadFromLS(): Cfg {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (raw) return JSON.parse(raw)
  } catch {
    /* ignore */
  }
  return { deviceId: '', syncToken: '' }
}

export const useConfigStore = defineStore('config', () => {
  const initial = loadFromLS()
  const deviceId = ref(initial.deviceId)
  const syncToken = ref(initial.syncToken)

  const isConfigured = computed(() => !!deviceId.value)

  function save() {
    localStorage.setItem(LS_KEY, JSON.stringify({ deviceId: deviceId.value, syncToken: syncToken.value }))
  }

  function clear() {
    deviceId.value = ''
    syncToken.value = ''
    localStorage.removeItem(LS_KEY)
  }

  return { deviceId, syncToken, isConfigured, save, clear }
})
```

- [ ] **Step 2: 修改 `src/api/http.ts`，改用 config store**

将 Step 4 中直读 localStorage 的 `loadCfg` 改为读 store：

```ts
import axios, { AxiosError, type AxiosInstance, type InternalAxiosRequestConfig } from 'axios'
import { APIResponse, ApiError, ErrorCode } from '@/types/api'
import { useConfigStore } from '@/stores/config'

export const http: AxiosInstance = axios.create({
  baseURL: '',
  timeout: 15000,
})

http.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const cfg = useConfigStore()
  if (!cfg.deviceId) {
    return Promise.reject(new ApiError(ErrorCode.HEADER_MISSING, '请先在配置中填写 Device ID'))
  }
  config.headers.set('X-Device-ID', cfg.deviceId)
  config.headers.set('X-Sync-Token', cfg.syncToken || '')
  config.headers.set('Content-Type', 'application/json')
  return config
})

http.interceptors.response.use(
  (resp) => {
    const body = resp.data as APIResponse<unknown>
    if (body.code !== ErrorCode.OK) {
      throw new ApiError(body.code, body.msg || `code=${body.code}`)
    }
    return body.data as any
  },
  (err) => {
    if (err instanceof AxiosError) {
      throw new ApiError(-1, err.message || '网络错误')
    }
    throw err
  }
)

declare module 'axios' {
  export interface AxiosInstance {
    get<T = unknown>(url: string, config?: InternalAxiosRequestConfig): Promise<T>
    post<T = unknown>(url: string, data?: unknown, config?: InternalAxiosRequestConfig): Promise<T>
    put<T = unknown>(url: string, data?: unknown, config?: InternalAxiosRequestConfig): Promise<T>
    delete<T = unknown>(url: string, config?: InternalAxiosRequestConfig): Promise<T>
  }
}
```

- [ ] **Step 3: 创建 `src/stores/recipes.ts`**

```ts
import { defineStore } from 'pinia'
import { ref } from 'vue'
import { recipeApi } from '@/api/recipes'
import type { Recipe, RecipeInput } from '@/types/recipe'
import { ApiError, ErrorCode } from '@/types/api'

export const useRecipesStore = defineStore('recipes', () => {
  const list = ref<Recipe[]>([])
  const current = ref<Recipe | null>(null)
  const loading = ref(false)

  async function fetchList() {
    loading.value = true
    try {
      list.value = await recipeApi.list()
    } finally {
      loading.value = false
    }
  }

  async function fetchOne(id: string) {
    loading.value = true
    try {
      current.value = await recipeApi.get(id)
    } finally {
      loading.value = false
    }
  }

  async function create(input: RecipeInput): Promise<string> {
    const data = await recipeApi.create(input)
    return data.id
  }

  async function update(id: string, input: RecipeInput) {
    await recipeApi.update(id, input)
  }

  async function remove(id: string) {
    await recipeApi.remove(id)
  }

  function clearCurrent() {
    current.value = null
  }

  return { list, current, loading, fetchList, fetchOne, create, update, remove, clearCurrent }
})

// 错误码映射供视图层使用
export function recipeErrorMsg(err: unknown): string {
  if (err instanceof ApiError) {
    switch (err.code) {
      case ErrorCode.HEADER_MISSING: return '请先配置 Device ID'
      case ErrorCode.TOKEN_INVALID: return 'Sync Token 与服务端不一致'
      case ErrorCode.NO_BACKUP: return '菜谱不存在'
      case ErrorCode.STORE_FAILED: return '保存失败：' + err.message
      case ErrorCode.SYNC_IN_PROGRESS: return '操作进行中，请稍后重试'
      default: return err.message
    }
  }
  return String(err)
}
```

- [ ] **Step 4: 创建 `src/stores/passwords.ts`**

```ts
import { defineStore } from 'pinia'
import { ref } from 'vue'
import { passwordApi } from '@/api/passwords'
import type { Password, PasswordInput } from '@/types/password'
import { ApiError, ErrorCode } from '@/types/api'

export const usePasswordsStore = defineStore('passwords', () => {
  const list = ref<Password[]>([])
  const current = ref<Password | null>(null)
  const loading = ref(false)

  async function fetchList() {
    loading.value = true
    try {
      list.value = await passwordApi.list()
    } finally {
      loading.value = false
    }
  }

  async function fetchOne(id: string) {
    loading.value = true
    try {
      current.value = await passwordApi.get(id)
    } finally {
      loading.value = false
    }
  }

  async function create(input: PasswordInput): Promise<string> {
    const data = await passwordApi.create(input)
    return data.id
  }

  async function update(id: string, input: PasswordInput) {
    await passwordApi.update(id, input)
  }

  async function remove(id: string) {
    await passwordApi.remove(id)
  }

  function clearCurrent() {
    current.value = null
  }

  return { list, current, loading, fetchList, fetchOne, create, update, remove, clearCurrent }
})

export function passwordErrorMsg(err: unknown): string {
  if (err instanceof ApiError) {
    switch (err.code) {
      case ErrorCode.HEADER_MISSING: return '请先配置 Device ID'
      case ErrorCode.TOKEN_INVALID: return 'Sync Token 与服务端不一致'
      case ErrorCode.NO_BACKUP: return '密码记录不存在'
      case ErrorCode.STORE_FAILED: return '保存失败：' + err.message
      case ErrorCode.SYNC_IN_PROGRESS: return '操作进行中，请稍后重试'
      default: return err.message
    }
  }
  return String(err)
}
```

- [ ] **Step 5: 创建 `src/stores/overview.ts`**

```ts
import { defineStore } from 'pinia'
import { ref } from 'vue'
import { syncApi } from '@/api/sync'
import { useRecipesStore } from './recipes'
import { usePasswordsStore } from './passwords'
import type { SyncInfo } from '@/types/api'

export const useOverviewStore = defineStore('overview', () => {
  const info = ref<SyncInfo | null>(null)
  const recipeCount = ref(0)
  const passwordCount = ref(0)
  const loading = ref(false)
  const error = ref('')

  // 并行 fetch 三个数据源，任一失败不影响其他
  async function refresh() {
    loading.value = true
    error.value = ''
    const recipes = useRecipesStore()
    const passwords = usePasswordsStore()

    const tasks: Array<Promise<void>> = [
      (async () => {
        try {
          info.value = await syncApi.getInfo()
        } catch (e) {
          // 首页显示「尚未同步」即可，不抛
          info.value = null
        }
      })(),
      (async () => {
        try {
          await recipes.fetchList()
          recipeCount.value = recipes.list.length
        } catch (e) {
          recipeCount.value = 0
        }
      })(),
      (async () => {
        try {
          await passwords.fetchList()
          passwordCount.value = passwords.list.length
        } catch (e) {
          passwordCount.value = 0
        }
      })(),
    ]
    await Promise.allSettled(tasks)
    loading.value = false
  }

  return { info, recipeCount, passwordCount, loading, error, refresh }
})
```

- [ ] **Step 6: 类型检查 + dev 启动验证**

```bash
cd server/internal/web/files
npx vue-tsc --noEmit
npm run dev
```

浏览器打开 `http://localhost:5173`，仍然看到脚手架占位（App.vue 还没改）。Ctrl+C 停止。

- [ ] **Step 7: 提交**

```bash
git add server/internal/web/files/src/
git commit -m "feat(web): add Pinia stores for config/recipes/passwords/overview"
```

---

## Task 5: 路由 + AppHeader + ConfigDrawer + EmptyState 骨架

**Files:**
- Create: `server/internal/web/files/src/router/index.ts`
- Create: `server/internal/web/files/src/components/AppHeader.vue` / `ConfigDrawer.vue` / `EmptyState.vue`
- Create: `server/internal/web/files/src/views/HomeView.vue` / `RecipesView.vue` / `PasswordsView.vue` / `SettingsView.vue`（4 个占位页面）
- Modify: `server/internal/web/files/src/App.vue`（接入路由 + 顶栏 + ConfigDrawer）
- Modify: `server/internal/web/files/src/main.ts`（注册 router）

**Interfaces:**
- Consumes: Task 2-4 的 store + API 层
- Produces:
  - `router` 实例（hash 模式，4 个路由）
  - `useConfigStore()` 全局可调
  - `AppHeader` / `ConfigDrawer` / `EmptyState` 三个通用组件
  - 4 个路由页面占位（Task 6-9 填充）

- [ ] **Step 1: 创建 `src/router/index.ts`**

```ts
import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router'

const routes: RouteRecordRaw[] = [
  { path: '/', name: 'home', component: () => import('@/views/HomeView.vue'), meta: { title: '总览' } },
  { path: '/recipes', name: 'recipes', component: () => import('@/views/RecipesView.vue'), meta: { title: '烹饪管理' } },
  { path: '/passwords', name: 'passwords', component: () => import('@/views/PasswordsView.vue'), meta: { title: '密码记录' } },
  { path: '/settings', name: 'settings', component: () => import('@/views/SettingsView.vue'), meta: { title: '配置' } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

export const router = createRouter({
  history: createWebHashHistory(),
  routes,
})
```

- [ ] **Step 2: 创建 `src/components/AppHeader.vue`**

```vue
<template>
  <header class="app-header">
    <div class="brand">
      <span class="brand-emoji">🛎️</span>
      <h1>{{ pageTitle }}</h1>
    </div>
    <el-menu
      mode="horizontal"
      :default-active="route.name as string"
      :ellipsis="false"
      router
      class="nav-menu"
    >
      <el-menu-item index="home">总览</el-menu-item>
      <el-menu-item index="recipes">烹饪</el-menu-item>
      <el-menu-item index="passwords">密码</el-menu-item>
      <el-menu-item index="settings">配置</el-menu-item>
    </el-menu>
    <el-button class="cfg-btn" :icon="Setting" circle @click="openDrawer" />
  </header>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { Setting } from '@element-plus/icons-vue'

const route = useRoute()
const pageTitle = computed(() => (route.meta.title as string) || 'PersonalButler')

const emit = defineEmits<{ (e: 'open-drawer'): void }>()
function openDrawer() {
  emit('open-drawer')
}
</script>

<style scoped lang="scss">
.app-header {
  display: flex;
  align-items: center;
  gap: 24px;
  padding: 0 24px;
  background: #fff;
  border-bottom: 1px solid #e5e5ea;
  position: sticky;
  top: 0;
  z-index: 10;
  height: 56px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}
.brand-emoji {
  font-size: 22px;
}
.brand h1 {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
}
.nav-menu {
  flex: 1;
  border-bottom: none !important;
}
.cfg-btn {
  flex-shrink: 0;
}
</style>
```

- [ ] **Step 3: 创建 `src/components/EmptyState.vue`**

```vue
<template>
  <div class="empty-state">
    <p class="big-emoji">{{ emoji }}</p>
    <p class="title">{{ title }}</p>
    <p v-if="hint" class="hint">{{ hint }}</p>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  emoji?: string
  title: string
  hint?: string
}>()
</script>

<style scoped lang="scss">
.empty-state {
  text-align: center;
  padding: 48px 24px;
  color: #8e8e93;
  background: #fff;
  border: 1px dashed #d1d1d6;
  border-radius: 8px;
}
.big-emoji {
  font-size: 48px;
  margin: 0 0 8px;
}
.title {
  margin: 0 0 4px;
  font-size: 14px;
}
.hint {
  margin: 0;
  font-size: 12px;
  color: #aeaeb2;
}
</style>
```

- [ ] **Step 4: 创建 `src/components/ConfigDrawer.vue`（最小占位版，Task 6 完整化）**

```vue
<template>
  <el-drawer v-model="visible" title="同步配置" direction="rtl" size="380px">
    <el-form label-position="top">
      <el-form-item label="Device ID">
        <el-input v-model="cfg.deviceId" placeholder="例如：8F5B2A3C-..." autocomplete="off" />
      </el-form-item>
      <el-form-item label="Sync Token">
        <el-input v-model="cfg.syncToken" type="password" show-password placeholder="与服务端 SYNC_TOKEN 一致" autocomplete="off" />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" @click="save">保存</el-button>
      </el-form-item>
    </el-form>
  </el-drawer>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useConfigStore } from '@/stores/config'

const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: boolean): void }>()

const cfg = useConfigStore()

const visible = ref(props.modelValue)
watch(() => props.modelValue, (v) => (visible.value = v))
watch(visible, (v) => emit('update:modelValue', v))

function save() {
  cfg.save()
  ElMessage.success('配置已保存')
  visible.value = false
}
</script>
```

- [ ] **Step 5: 创建 4 个占位 view**

`src/views/HomeView.vue`：
```vue
<template>
  <div class="page"><EmptyState emoji="📊" title="总览页 - Task 7 实现" /></div>
</template>
<script setup lang="ts">
import EmptyState from '@/components/EmptyState.vue'
</script>
<style scoped>
.page { padding: 24px; }
</style>
```

`src/views/RecipesView.vue`：
```vue
<template>
  <div class="page"><EmptyState emoji="🍲" title="烹饪管理页 - Task 8 实现" /></div>
</template>
<script setup lang="ts">
import EmptyState from '@/components/EmptyState.vue'
</script>
<style scoped>
.page { padding: 24px; }
</style>
```

`src/views/PasswordsView.vue`：
```vue
<template>
  <div class="page"><EmptyState emoji="🔑" title="密码记录页 - Task 9 实现" /></div>
</template>
<script setup lang="ts">
import EmptyState from '@/components/EmptyState.vue'
</script>
<style scoped>
.page { padding: 24px; }
</style>
```

`src/views/SettingsView.vue`：
```vue
<template>
  <div class="page"><EmptyState emoji="⚙️" title="配置页 - Task 6 实现" /></div>
</template>
<script setup lang="ts">
import EmptyState from '@/components/EmptyState.vue'
</script>
<style scoped>
.page { padding: 24px; }
</style>
```

- [ ] **Step 6: 修改 `src/App.vue`，接入路由 + 顶栏 + ConfigDrawer + 未配置自动唤起**

```vue
<template>
  <div class="app-shell">
    <AppHeader @open-drawer="drawerVisible = true" />
    <main class="app-main">
      <router-view />
    </main>
    <ConfigDrawer v-model="drawerVisible" />
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ElMessage } from 'element-plus'
import AppHeader from '@/components/AppHeader.vue'
import ConfigDrawer from '@/components/ConfigDrawer.vue'
import { useConfigStore } from '@/stores/config'

const drawerVisible = ref(false)
const cfg = useConfigStore()
const route = useRoute()

// 进入任意页面时，若 deviceId 为空 → 自动唤起配置抽屉
onMounted(() => {
  if (!cfg.isConfigured) {
    drawerVisible.value = true
    ElMessage.warning('请先配置 Device ID')
  }
})

// 切换路由时滚动到顶部
watch(() => route.path, () => window.scrollTo(0, 0))
</script>

<style scoped lang="scss">
.app-shell {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}
.app-main {
  flex: 1;
}
</style>
```

- [ ] **Step 7: 修改 `src/main.ts`，注册 router**

```ts
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { router } from './router'
import 'element-plus/theme-chalk/dark/css-vars.css'
import './styles/global.scss'

const app = createApp(App)
app.use(createPinia())
app.use(router)
app.mount('#app')
```

- [ ] **Step 8: dev 启动验证**

```bash
cd server/internal/web/files
npm run dev
```

打开 `http://localhost:5173`：
- 顶栏显示 🛎️ + 当前页面标题 + 4 个导航项 + ⚙️ 按钮
- 默认在「总览」路由，点击导航能切换到其他 3 个页面
- 首次进入自动弹配置抽屉，输入任意 Device ID 保存后不再弹

Ctrl+C 停止。

- [ ] **Step 9: 提交**

```bash
git add server/internal/web/files/src/
git commit -m "feat(web): wire router, AppHeader, ConfigDrawer with 4 placeholder views"
```

---

## Task 6: 配置页 + ConfigDrawer 完整功能

**Files:**
- Modify: `server/internal/web/files/src/components/ConfigDrawer.vue`（加测试连接）
- Modify: `server/internal/web/files/src/views/SettingsView.vue`（独立路由版完整配置）
- Create: `server/internal/web/files/src/composables/useToast.ts`

**Interfaces:**
- Consumes: Task 4 的 config store + Task 3 的 syncApi
- Produces: 完整的配置 UI（保存 / 清空 / 测试连接），全局错误码 → 中文消息映射

- [ ] **Step 1: 创建 `src/composables/useToast.ts`**

```ts
import { ElMessage, ElMessageBox } from 'element-plus'
import { ApiError, ErrorCode } from '@/types/api'

// 统一把 ApiError 转中文消息显示
export function useToast() {
  function showError(err: unknown, prefix = '') {
    let msg: string
    if (err instanceof ApiError) {
      switch (err.code) {
        case ErrorCode.HEADER_MISSING: msg = '请先配置 Device ID'; break
        case ErrorCode.TOKEN_INVALID: msg = 'Sync Token 与服务端不一致，请检查配置'; break
        case ErrorCode.NO_BACKUP: msg = '尚无备份数据'; break
        case ErrorCode.SYNC_IN_PROGRESS: msg = '操作进行中，请稍后重试'; break
        case ErrorCode.INTERNAL: msg = '服务异常，请稍后重试'; break
        default: msg = err.message
      }
    } else {
      msg = String(err)
    }
    ElMessage.error(prefix ? `${prefix}：${msg}` : msg)
  }

  function success(msg: string) {
    ElMessage.success(msg)
  }

  function warn(msg: string) {
    ElMessage.warning(msg)
  }

  async function confirm(content: string, title = '确认操作'): Promise<boolean> {
    try {
      await ElMessageBox.confirm(content, title, { type: 'warning' })
      return true
    } catch {
      return false
    }
  }

  return { showError, success, warn, confirm }
}
```

- [ ] **Step 2: 重写 `src/components/ConfigDrawer.vue`**

```vue
<template>
  <el-drawer v-model="visible" title="同步配置" direction="rtl" size="380px">
    <el-form label-position="top">
      <el-form-item label="Device ID">
        <el-input v-model="cfg.deviceId" placeholder="例如：8F5B2A3C-..." autocomplete="off" />
      </el-form-item>
      <el-form-item label="Sync Token">
        <el-input v-model="cfg.syncToken" type="password" show-password placeholder="与服务端 SYNC_TOKEN 一致" autocomplete="off" />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" @click="save">保存</el-button>
        <el-button @click="testConnection" :loading="testing">测试连接</el-button>
        <el-button type="danger" plain @click="clear">清空配置</el-button>
      </el-form-item>
      <p class="hint">
        在 iOS 端「我的 → 局域网同步」可看到 Device ID 前缀；Token 与服务端 SYNC_TOKEN 一致即可。
      </p>
    </el-form>
  </el-drawer>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useConfigStore } from '@/stores/config'
import { syncApi } from '@/api/sync'
import { useToast } from '@/composables/useToast'

const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: boolean): void }>()

const cfg = useConfigStore()
const toast = useToast()
const testing = ref(false)

const visible = ref(props.modelValue)
watch(() => props.modelValue, (v) => (visible.value = v))
watch(visible, (v) => emit('update:modelValue', v))

function save() {
  cfg.save()
  ElMessage.success('配置已保存')
  visible.value = false
}

async function testConnection() {
  if (!cfg.deviceId) {
    toast.warn('请先填写 Device ID')
    return
  }
  cfg.save() // 测试前先持久化，让拦截器能读到
  testing.value = true
  try {
    const info = await syncApi.getInfo()
    ElMessage.success(`连接成功，共 ${info.totalCount} 条数据，最近同步：${formatTime(info.syncTimestamp)}`)
  } catch (err) {
    toast.showError(err, '连接失败')
  } finally {
    testing.value = false
  }
}

async function clear() {
  if (!(await toast.confirm('确认清空配置？此操作不可撤销。', '清空配置'))) return
  cfg.clear()
  ElMessage.success('配置已清空')
}

function formatTime(ts: number): string {
  return new Date(ts * 1000).toLocaleString('zh-Hans')
}
</script>

<style scoped>
.hint {
  color: #8e8e93;
  font-size: 12px;
  margin: 8px 0 0;
}
</style>
```

- [ ] **Step 3: 重写 `src/views/SettingsView.vue`（独立路由版完整配置）**

```vue
<template>
  <div class="settings-page">
    <el-card>
      <template #header>同步配置</template>
      <el-form label-position="top" class="settings-form">
        <el-form-item label="Device ID">
          <el-input v-model="cfg.deviceId" placeholder="例如：8F5B2A3C-..." autocomplete="off" />
        </el-form-item>
        <el-form-item label="Sync Token">
          <el-input v-model="cfg.syncToken" type="password" show-password placeholder="与服务端 SYNC_TOKEN 一致" autocomplete="off" />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="save">保存</el-button>
          <el-button @click="testConnection" :loading="testing">测试连接</el-button>
          <el-button type="danger" plain @click="clear">清空配置</el-button>
        </el-form-item>
        <p class="hint">
          Device ID 与 iOS 端 AppSyncConfig.deviceID 一致；Token 与服务端 SYNC_TOKEN 环境变量一致。两项保存在浏览器 localStorage。
        </p>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { ElMessage } from 'element-plus'
import { useConfigStore } from '@/stores/config'
import { syncApi } from '@/api/sync'
import { useToast } from '@/composables/useToast'

const cfg = useConfigStore()
const toast = useToast()
const testing = ref(false)

function save() {
  cfg.save()
  ElMessage.success('配置已保存')
}

async function testConnection() {
  if (!cfg.deviceId) {
    toast.warn('请先填写 Device ID')
    return
  }
  cfg.save()
  testing.value = true
  try {
    const info = await syncApi.getInfo()
    ElMessage.success(`连接成功，共 ${info.totalCount} 条数据，最近同步：${formatTime(info.syncTimestamp)}`)
  } catch (err) {
    toast.showError(err, '连接失败')
  } finally {
    testing.value = false
  }
}

async function clear() {
  if (!(await toast.confirm('确认清空配置？此操作不可撤销。', '清空配置'))) return
  cfg.clear()
  ElMessage.success('配置已清空')
}

function formatTime(ts: number): string {
  return new Date(ts * 1000).toLocaleString('zh-Hans')
}
</script>

<style scoped lang="scss">
.settings-page {
  padding: 24px;
  max-width: 720px;
  margin: 0 auto;
}
.settings-form {
  max-width: 480px;
}
.hint {
  color: #8e8e93;
  font-size: 12px;
  margin: 8px 0 0;
}
</style>
```

- [ ] **Step 4: dev 启动手动验证**

启动 Go 服务（端口 8090）+ `npm run dev`，在浏览器：
- 访问 `http://localhost:5173/#/settings`，应看到独立配置页
- 填入错误的 Token → 点测试连接 → 显示「Sync Token 与服务端不一致」
- 填入正确的 Token → 点测试连接 → 显示成功 + 条数
- 点顶栏 ⚙️ → 抽屉版配置同样可用

- [ ] **Step 5: 提交**

```bash
git add server/internal/web/files/src/
git commit -m "feat(web): implement full config page and drawer with test-connection"
```

---

## Task 7: 首页总览

**Files:**
- Modify: `server/internal/web/files/src/views/HomeView.vue`

**Interfaces:**
- Consumes: Task 4 的 overview store + Task 6 的 useToast
- Produces: 完整的首页（4 张卡片：同步状态 / 菜谱总数 / 密码总数 / 使用提示）

- [ ] **Step 1: 重写 `src/views/HomeView.vue`**

```vue
<template>
  <div class="home-page">
    <el-row :gutter="16" v-loading="store.loading">
      <el-col :xs="24" :sm="12" :md="8">
        <el-card class="stat-card">
          <template #header>同步状态</template>
          <template v-if="!cfg.isConfigured">
            <p class="muted">请先配置 Device ID</p>
            <el-button type="primary" size="small" @click="goSettings">立即配置</el-button>
          </template>
          <template v-else-if="store.info">
            <p>最近同步：<strong>{{ formatTime(store.info.syncTimestamp) }}</strong></p>
            <p>App 版本：{{ store.info.appVersion }}</p>
            <p>数据版本：v{{ store.info.dataVersion }}</p>
            <p>总条数：{{ store.info.totalCount }}</p>
          </template>
          <template v-else>
            <p class="muted">尚未同步</p>
          </template>
        </el-card>
      </el-col>

      <el-col :xs="24" :sm="12" :md="8">
        <el-card class="stat-card">
          <template #header>菜谱</template>
          <p class="big-num">{{ store.recipeCount }}</p>
          <p class="muted">条菜谱</p>
          <el-button type="primary" size="small" @click="goRecipes">立即管理</el-button>
        </el-card>
      </el-col>

      <el-col :xs="24" :sm="12" :md="8">
        <el-card class="stat-card">
          <template #header>密码</template>
          <p class="big-num">{{ store.passwordCount }}</p>
          <p class="muted">条密码记录</p>
          <el-button type="primary" size="small" @click="goPasswords">立即管理</el-button>
        </el-card>
      </el-col>
    </el-row>

    <el-card class="tip-card">
      <template #header>使用提示</template>
      <el-collapse>
        <el-collapse-item title="iOS 上传 → Web 编辑 → iOS 下载（推荐顺序）" name="1">
          <p>1. iOS 端先做一次<strong>上传</strong>，把本地状态推到服务端</p>
          <p>2. 浏览器打开 /web，配置 Device ID + Token</p>
          <p>3. 在 Web 端录入 / 编辑数据，保存到 DB</p>
          <p>4. iOS 端做<strong>下载</strong> → 本地数据被服务端数据全量替换</p>
        </el-collapse-item>
        <el-collapse-item title="⚠️ 注意 upload 会覆盖 Web 录入" name="2">
          <p>iOS 端 upload 是全量覆盖语义（DELETE WHERE device_id + INSERT）。如果 iOS 在 Web 录入后再 upload，会<strong>清空</strong> Web 录入的数据。</p>
          <p>请严格遵循「先 iOS upload → 再 Web 编辑 → 再 iOS download」的顺序。</p>
        </el-collapse-item>
      </el-collapse>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useOverviewStore } from '@/stores/overview'
import { useConfigStore } from '@/stores/config'

const router = useRouter()
const store = useOverviewStore()
const cfg = useConfigStore()

onMounted(() => {
  if (cfg.isConfigured) {
    store.refresh()
  }
})

function goSettings() {
  router.push('/settings')
}
function goRecipes() {
  router.push('/recipes')
}
function goPasswords() {
  router.push('/passwords')
}
function formatTime(ts: number): string {
  return new Date(ts * 1000).toLocaleString('zh-Hans')
}
</script>

<style scoped lang="scss">
.home-page {
  padding: 24px;
}
.stat-card {
  margin-bottom: 16px;
  min-height: 200px;
}
.big-num {
  font-size: 36px;
  font-weight: 600;
  margin: 8px 0;
}
.muted {
  color: #8e8e93;
  font-size: 13px;
}
.tip-card {
  margin-top: 16px;
}
.tip-card p {
  margin: 6px 0;
  font-size: 13px;
}
</style>
```

- [ ] **Step 2: dev 验证**

启动 Go 服务 + `npm run dev`，访问 `http://localhost:5173/`：
- 4 张卡片正常展示（同步状态 / 菜谱 / 密码 / 使用提示）
- 数字与各业务页列表长度一致（如果 Task 1 已造了密码数据，密码卡片应显示对应条数）
- 点「立即管理」按钮能跳到对应路由

- [ ] **Step 3: 提交**

```bash
git add server/internal/web/files/src/views/HomeView.vue
git commit -m "feat(web): implement home overview page with stats and tips"
```

---

## Task 8: 烹饪管理页（迁移现有 app.js 功能）

**Files:**
- Create: `server/internal/web/files/src/composables/useImageCompress.ts`
- Create: `server/internal/web/files/src/components/ImagePicker.vue` / `IngredientEditor.vue` / `RecipeForm.vue`
- Modify: `server/internal/web/files/src/views/RecipesView.vue`

**Interfaces:**
- Consumes: Task 3-4 的 recipes store / recipeApi / types；Task 6 的 useToast
- Produces: 完整菜谱 CRUD 页面（左侧列表 + 右侧表单 + 食材子项 + 图片上传）

- [ ] **Step 1: 创建 `src/composables/useImageCompress.ts`**

迁移 app.js 的 `fileToBase64` 逻辑：canvas 缩放到 512px max side + JPEG 0.7 质量。

```ts
// 把 File 读成 base64 字符串，同时缩到 512px max side + JPEG 0.7
// 与 iOS ImageProcessor.swift / 旧 app.js 的约定一致
export function useImageCompress() {
  function fileToBase64(file: File): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = (e) => {
        const img = new Image()
        img.onload = () => {
          const MAX = 512
          let { width, height } = img
          if (width > height && width > MAX) {
            height = Math.round((height * MAX) / width)
            width = MAX
          } else if (height > MAX) {
            width = Math.round((width * MAX) / height)
            height = MAX
          }
          const canvas = document.createElement('canvas')
          canvas.width = width
          canvas.height = height
          const ctx = canvas.getContext('2d')!
          ctx.drawImage(img, 0, 0, width, height)
          const dataUrl = canvas.toDataURL('image/jpeg', 0.7)
          // 剥离 "data:image/jpeg;base64," 前缀，与服务端约定一致
          resolve(dataUrl.split(',')[1])
        }
        img.onerror = () => reject(new Error('图片解析失败'))
        img.src = e.target!.result as string
      }
      reader.onerror = () => reject(new Error('文件读取失败'))
      reader.readAsDataURL(file)
    })
  }

  return { fileToBase64 }
}
```

- [ ] **Step 2: 创建 `src/components/ImagePicker.vue`**

```vue
<template>
  <div class="image-picker">
    <img v-if="previewSrc" :src="previewSrc" class="icon-preview" alt="预览" />
    <el-upload
      :auto-upload="false"
      :show-file-list="false"
      accept="image/jpeg,image/png"
      :on-change="onChange"
    >
      <el-button size="small">选择图片</el-button>
    </el-upload>
    <el-button v-if="previewSrc" size="small" @click="clear">清除</el-button>
  </div>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import type { UploadFile } from 'element-plus'
import { useImageCompress } from '@/composables/useImageCompress'
import { useToast } from '@/composables/useToast'

const props = defineProps<{ modelValue?: string | null }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: string | null): void }>()

const { fileToBase64 } = useImageCompress()
const toast = useToast()
const previewSrc = ref<string>('')

// 初始化预览（编辑场景从 base64 还原 dataURL）
watch(
  () => props.modelValue,
  (v) => {
    if (v) {
      previewSrc.value = `data:image/jpeg;base64,${v}`
    } else {
      previewSrc.value = ''
    }
  },
  { immediate: true }
)

async function onChange(file: UploadFile) {
  if (!file.raw) return
  try {
    const base64 = await fileToBase64(file.raw)
    previewSrc.value = `data:image/jpeg;base64,${base64}`
    emit('update:modelValue', base64)
  } catch (err) {
    toast.showError(err, '图片处理失败')
  }
}

function clear() {
  previewSrc.value = ''
  emit('update:modelValue', null)
}
</script>

<style scoped lang="scss">
.image-picker {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.icon-preview {
  width: 56px;
  height: 56px;
  border-radius: 8px;
  object-fit: cover;
  border: 1px solid #d1d1d6;
}
</style>
```

- [ ] **Step 3: 创建 `src/components/IngredientEditor.vue`**

```vue
<template>
  <div class="ingredient-editor">
    <div v-for="(ing, idx) in ingredients" :key="idx" class="ing-row">
      <el-input v-model="ing.name" placeholder="食材名" class="col-name" />
      <el-input v-model="ing.amount" placeholder="用量" class="col-amount" />
      <el-input-number v-model="ing.order" :min="0" :controls="false" placeholder="顺序" class="col-order" />
      <el-button type="danger" :icon="Delete" circle size="small" @click="remove(idx)" />
    </div>
    <el-button size="small" @click="add">+ 添加食材</el-button>
    <p class="hint">行顺序由「顺序」数字控制，相等时按录入顺序。空行会被自动跳过。</p>
  </div>
</template>

<script setup lang="ts">
import { Delete } from '@element-plus/icons-vue'
import type { RecipeIngredient } from '@/types/recipe'

const props = defineProps<{ modelValue: Array<RecipeIngredient & { id?: string }> }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: Array<RecipeIngredient & { id?: string }>): void }>()

// 直接 mutate props.modelValue（Pinia store 中也是数组引用），同时 emit 触发响应
function add() {
  props.modelValue.push({ id: undefined, name: '', amount: '', order: props.modelValue.length })
  emit('update:modelValue', props.modelValue)
}
function remove(idx: number) {
  props.modelValue.splice(idx, 1)
  emit('update:modelValue', props.modelValue)
}
</script>

<style scoped lang="scss">
.ing-row {
  display: grid;
  grid-template-columns: 2fr 2fr 1fr auto;
  gap: 8px;
  margin-bottom: 8px;
  align-items: center;
}
.hint {
  color: #8e8e93;
  font-size: 12px;
  margin: 8px 0 0;
}
</style>
```

- [ ] **Step 4: 创建 `src/components/RecipeForm.vue`**

```vue
<template>
  <el-card class="recipe-form-card">
    <el-form label-position="top" @submit.prevent="onSubmit">
      <el-form-item label="名称" required>
        <el-input v-model="form.name" placeholder="番茄炒蛋" required />
      </el-form-item>

      <el-row :gutter="12">
        <el-col :span="8">
          <el-form-item label="Emoji 图标">
            <el-input v-model="form.emoji" maxlength="8" placeholder="🍲" />
          </el-form-item>
        </el-col>
        <el-col :span="8">
          <el-form-item label="难度">
            <el-select v-model="form.difficulty">
              <el-option label="简单" value="easy" />
              <el-option label="中等" value="medium" />
              <el-option label="进阶" value="hard" />
            </el-select>
          </el-form-item>
        </el-col>
        <el-col :span="8">
          <el-form-item label="分类">
            <el-select v-model="form.category">
              <el-option label="家常菜" value="home" />
              <el-option label="面食" value="noodle" />
              <el-option label="汤羹" value="soup" />
              <el-option label="甜品" value="dessert" />
            </el-select>
          </el-form-item>
        </el-col>
      </el-row>

      <el-form-item label="分钟">
        <el-input-number v-model="form.minutes" :min="1" />
      </el-form-item>

      <el-form-item label="图片图标（可选，JPEG/PNG ≤ 512px）">
        <ImagePicker v-model="form.iconImageBase64" />
      </el-form-item>

      <el-form-item label="食材">
        <IngredientEditor v-model="form.ingredients" />
      </el-form-item>

      <el-form-item label="步骤（每行一条）">
        <el-input v-model="form.steps" type="textarea" :rows="6" placeholder="1. 鸡蛋打散加少许盐&#10;2. 番茄切块" />
      </el-form-item>

      <el-form-item label="小贴士">
        <el-input v-model="form.tips" type="textarea" :rows="3" placeholder="可选，例如：盐别放多" />
      </el-form-item>

      <el-collapse>
        <el-collapse-item title="旧版食材文本（迁移用，一般留空）" name="legacy">
          <el-input v-model="form.ingredientsLegacyRaw" type="textarea" :rows="2" placeholder="兼容字段，新数据请用上面的食材列表" />
        </el-collapse-item>
      </el-collapse>

      <div class="form-actions">
        <el-button type="primary" :loading="saving" @click="onSubmit">保存</el-button>
        <el-button @click="onCancel">取消</el-button>
        <el-button v-if="isEdit" type="danger" @click="onDelete">删除</el-button>
      </div>
    </el-form>
  </el-card>
</template>

<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import ImagePicker from './ImagePicker.vue'
import IngredientEditor from './IngredientEditor.vue'
import { useRecipesStore, recipeErrorMsg } from '@/stores/recipes'
import { useToast } from '@/composables/useToast'
import type { Recipe, RecipeInput } from '@/types/recipe'

const props = defineProps<{ recipe: Recipe | null }>()
const emit = defineEmits<{ (e: 'saved', id: string): void; (e: 'cancel'): void; (e: 'delete'): void }>()

const store = useRecipesStore()
const toast = useToast()
const saving = ref(false)

const isEdit = computed(() => !!props.recipe)

interface FormState {
  id?: string
  name: string
  emoji: string
  difficulty: string
  minutes: number
  category: string
  steps: string
  tips: string
  ingredientsLegacyRaw: string
  iconImageBase64: string | null
  ingredients: Array<RecipeIngredient & { id?: string }>
}

function emptyForm(): FormState {
  return {
    name: '',
    emoji: '🍲',
    difficulty: 'easy',
    minutes: 30,
    category: 'home',
    steps: '',
    tips: '',
    ingredientsLegacyRaw: '',
    iconImageBase64: null,
    ingredients: [],
  }
}

const form = reactive<FormState>(emptyForm())

watch(
  () => props.recipe,
  (r) => {
    Object.assign(form, emptyForm())
    if (r) {
      form.id = r.id
      form.name = r.name
      form.emoji = r.emoji || '🍲'
      form.difficulty = r.difficulty || 'easy'
      form.minutes = r.minutes || 30
      form.category = r.category || 'home'
      form.steps = r.steps || ''
      form.tips = r.tips || ''
      form.ingredientsLegacyRaw = r.ingredientsLegacyRaw || ''
      form.iconImageBase64 = r.iconImageBase64 || null
      form.ingredients = (r.ingredients || []).map((i) => ({ ...i }))
    }
  },
  { immediate: true }
)

async function onSubmit() {
  if (!form.name.trim()) {
    toast.warn('请填写名称')
    return
  }
  saving.value = true
  try {
    const payload: RecipeInput = {
      id: form.id,
      name: form.name.trim(),
      emoji: form.emoji.trim() || '🍲',
      difficulty: form.difficulty,
      minutes: form.minutes,
      category: form.category,
      steps: form.steps,
      tips: form.tips,
      ingredientsLegacyRaw: form.ingredientsLegacyRaw,
      iconImageBase64: form.iconImageBase64,
      ingredients: form.ingredients
        .filter((i) => i.name.trim() || i.amount.trim())
        .map((i) => ({ id: i.id, name: i.name.trim(), amount: i.amount.trim(), order: i.order })),
    }
    let savedId: string
    if (payload.id) {
      await store.update(payload.id, payload)
      savedId = payload.id
    } else {
      savedId = await store.create(payload)
    }
    toast.success('已保存')
    emit('saved', savedId)
  } catch (err) {
    toast.showError(err, recipeErrorMsg(err))
  } finally {
    saving.value = false
  }
}

function onCancel() {
  emit('cancel')
}

async function onDelete() {
  if (!form.id) return
  if (!(await toast.confirm('确认删除该菜谱？该操作不可撤销。', '删除确认'))) return
  try {
    await store.remove(form.id)
    toast.success('已删除')
    emit('delete')
  } catch (err) {
    toast.showError(err, recipeErrorMsg(err))
  }
}
</script>

<style scoped lang="scss">
.form-actions {
  display: flex;
  gap: 8px;
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid #e5e5ea;
}
</style>
```

- [ ] **Step 5: 重写 `src/views/RecipesView.vue`**

```vue
<template>
  <div class="recipes-view">
    <aside class="list-pane">
      <div class="list-header">
        <el-input v-model="keyword" placeholder="搜索菜谱名" :prefix-icon="Search" clearable size="small" />
        <el-select v-model="categoryFilter" size="small" class="cat-filter">
          <el-option label="全部分类" value="" />
          <el-option label="家常菜" value="home" />
          <el-option label="面食" value="noodle" />
          <el-option label="汤羹" value="soup" />
          <el-option label="甜品" value="dessert" />
        </el-select>
        <el-button type="primary" size="small" @click="onNew">+ 新建</el-button>
      </div>
      <div class="recipe-list" v-loading="store.loading">
        <p v-if="!store.list.length" class="empty">还没有菜谱，点击「+ 新建」开始</p>
        <div
          v-for="r in filteredList"
          :key="r.id"
          class="recipe-item"
          :class="{ active: r.id === currentId }"
          @click="onSelect(r.id)"
        >
          <span class="emoji">{{ r.emoji || '🍲' }}</span>
          <span class="name">{{ r.name }}</span>
          <span class="meta">{{ r.minutes }}min · {{ difficultyLabel(r.difficulty) }}</span>
        </div>
      </div>
    </aside>

    <section class="form-pane">
      <RecipeForm
        v-if="store.current || mode === 'create'"
        :recipe="store.current"
        @saved="onSaved"
        @cancel="onCancel"
        @delete="onDeleted"
      />
      <EmptyState v-else emoji="👈" title="点击「+ 新建」或在左侧选择一条菜谱开始录入" hint="保存后，iOS 端走「局域网同步 → 下载」即可恢复到本地" />
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Search } from '@element-plus/icons-vue'
import RecipeForm from '@/components/RecipeForm.vue'
import EmptyState from '@/components/EmptyState.vue'
import { useRecipesStore, recipeErrorMsg } from '@/stores/recipes'
import { useToast } from '@/composables/useToast'

const store = useRecipesStore()
const toast = useToast()

const keyword = ref('')
const categoryFilter = ref('')
const currentId = ref<string | null>(null)
const mode = ref<'view' | 'create'>('view')

const filteredList = computed(() =>
  store.list.filter((r) => {
    const kw = keyword.value.trim().toLowerCase()
    const matchKw = !kw || r.name.toLowerCase().includes(kw)
    const matchCat = !categoryFilter.value || r.category === categoryFilter.value
    return matchKw && matchCat
  })
)

onMounted(async () => {
  try {
    await store.fetchList()
  } catch (err) {
    toast.showError(err, recipeErrorMsg(err))
  }
})

function difficultyLabel(v: string): string {
  return ({ easy: '简单', medium: '中等', hard: '进阶' } as Record<string, string>)[v] || v
}

function onNew() {
  currentId.value = null
  store.clearCurrent()
  mode.value = 'create'
}

async function onSelect(id: string) {
  currentId.value = id
  mode.value = 'view'
  try {
    await store.fetchOne(id)
  } catch (err) {
    toast.showError(err, recipeErrorMsg(err))
  }
}

async function onSaved(id: string) {
  currentId.value = id
  mode.value = 'view'
  await store.fetchList()
  await store.fetchOne(id)
}

function onCancel() {
  store.clearCurrent()
  mode.value = 'view'
}

async function onDeleted() {
  currentId.value = null
  store.clearCurrent()
  mode.value = 'view'
  await store.fetchList()
}
</script>

<style scoped lang="scss">
.recipes-view {
  display: grid;
  grid-template-columns: 320px 1fr;
  gap: 16px;
  padding: 16px 24px;
  align-items: start;
}
@media (max-width: 960px) {
  .recipes-view {
    grid-template-columns: 1fr;
  }
}
.list-pane {
  position: sticky;
  top: 72px;
}
.list-header {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 12px;
}
.cat-filter {
  width: 100%;
}
.recipe-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.recipe-item {
  display: flex;
  align-items: center;
  gap: 10px;
  background: #fff;
  border: 1px solid #e5e5ea;
  border-radius: 8px;
  padding: 10px 12px;
  cursor: pointer;
  transition: border-color 0.15s, background 0.15s;
}
.recipe-item:hover {
  border-color: #007aff;
}
.recipe-item.active {
  background: #f0f8ff;
  border-color: #007aff;
}
.recipe-item .emoji {
  font-size: 18px;
  flex-shrink: 0;
}
.recipe-item .name {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.recipe-item .meta {
  font-size: 11px;
  color: #8e8e93;
  flex-shrink: 0;
}
.empty {
  color: #8e8e93;
  text-align: center;
  padding: 24px;
  font-size: 13px;
}
</style>
```

- [ ] **Step 6: dev 端到端验证**

启动 Go 服务 + `npm run dev`，访问 `http://localhost:5173/#/recipes`：
- 列表加载显示已有菜谱
- 点「+ 新建」→ 表单出现 → 填写名称/食材/上传图片 → 保存 → 列表刷新 + 表单切换为编辑态出现「删除」按钮
- 编辑现有菜谱 → 修改后保存 → 重新加载看到最新状态
- 删除菜谱 → 二次确认 → 列表移除

- [ ] **Step 7: 提交**

```bash
git add server/internal/web/files/src/
git commit -m "feat(web): implement recipe management page with form, ingredients, image picker"
```

---

## Task 9: 密码记录页

**Files:**
- Create: `server/internal/web/files/src/components/PasswordForm.vue`
- Modify: `server/internal/web/files/src/views/PasswordsView.vue`

**Interfaces:**
- Consumes: Task 3-4 的 passwords store；Task 6 的 useToast
- Produces: 完整密码 CRUD 页面（列表 + 表单 + 生成随机密码）

- [ ] **Step 1: 创建 `src/components/PasswordForm.vue`**

```vue
<template>
  <el-card class="password-form-card">
    <el-form label-position="top" @submit.prevent="onSubmit">
      <el-form-item label="平台名称" required>
        <el-input v-model="form.platform" placeholder="GitHub" required />
      </el-form-item>

      <el-form-item label="账号" required>
        <el-input v-model="form.account" placeholder="alice@example.com" required />
      </el-form-item>

      <el-form-item label="密码" required>
        <div class="password-row">
          <el-input v-model="form.passwordPlain" type="password" show-password placeholder="••••••••" required />
          <el-button @click="generatePassword">生成随机</el-button>
        </div>
      </el-form-item>

      <el-form-item label="分类">
        <el-select v-model="form.category">
          <el-option label="社交" value="social" />
          <el-option label="办公" value="office" />
          <el-option label="金融" value="finance" />
          <el-option label="自定义" value="custom" />
        </el-select>
      </el-form-item>

      <el-form-item label="展示辅文">
        <el-input v-model="form.typeText" placeholder="例如：社交 · 常用" />
      </el-form-item>

      <div class="form-actions">
        <el-button type="primary" :loading="saving" @click="onSubmit">保存</el-button>
        <el-button @click="onCancel">取消</el-button>
        <el-button v-if="isEdit" type="danger" @click="onDelete">删除</el-button>
      </div>
    </el-form>
  </el-card>
</template>

<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { usePasswordsStore, passwordErrorMsg } from '@/stores/passwords'
import { useToast } from '@/composables/useToast'
import type { Password, PasswordInput } from '@/types/password'

const props = defineProps<{ password: Password | null }>()
const emit = defineEmits<{ (e: 'saved', id: string): void; (e: 'cancel'): void; (e: 'delete'): void }>()

const store = usePasswordsStore()
const toast = useToast()
const saving = ref(false)

const isEdit = computed(() => !!props.password)

interface FormState {
  id?: string
  platform: string
  account: string
  passwordPlain: string
  typeText: string
  category: string
}

function emptyForm(): FormState {
  return {
    platform: '',
    account: '',
    passwordPlain: '',
    typeText: '',
    category: 'social',
  }
}

const form = reactive<FormState>(emptyForm())

watch(
  () => props.password,
  (p) => {
    Object.assign(form, emptyForm())
    if (p) {
      form.id = p.id
      form.platform = p.platform
      form.account = p.account
      form.passwordPlain = p.passwordPlain
      form.typeText = p.typeText
      form.category = p.category || 'social'
    }
  },
  { immediate: true }
)

// crypto.getRandomValues 生成 12 位（大写+小写+数字+特殊符号各 3 位）
function generatePassword() {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
  const lower = 'abcdefghijkmnpqrstuvwxyz'
  const digit = '23456789'
  const special = '!@#$%^&*-_=+'
  const pools = [upper, lower, digit, special]
  const out: string[] = []
  const buf = new Uint32Array(12)
  crypto.getRandomValues(buf)
  // 先从每个池子各取 3 位
  for (let p = 0; p < 4; p++) {
    for (let i = 0; i < 3; i++) {
      out.push(pools[p][buf[p * 3 + i] % pools[p].length])
    }
  }
  // 简单洗牌
  for (let i = out.length - 1; i > 0; i--) {
    const j = buf[i] % (i + 1)
    ;[out[i], out[j]] = [out[j], out[i]]
  }
  form.passwordPlain = out.join('')
}

async function onSubmit() {
  if (!form.platform.trim()) {
    toast.warn('请填写平台名称')
    return
  }
  if (!form.account.trim()) {
    toast.warn('请填写账号')
    return
  }
  if (!form.passwordPlain) {
    toast.warn('请填写密码')
    return
  }
  saving.value = true
  try {
    const payload: PasswordInput = {
      id: form.id,
      platform: form.platform.trim(),
      account: form.account.trim(),
      passwordPlain: form.passwordPlain,
      typeText: form.typeText,
      category: form.category,
    }
    let savedId: string
    if (payload.id) {
      await store.update(payload.id, payload)
      savedId = payload.id
    } else {
      savedId = await store.create(payload)
    }
    toast.success('已保存')
    emit('saved', savedId)
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  } finally {
    saving.value = false
  }
}

function onCancel() {
  emit('cancel')
}

async function onDelete() {
  if (!form.id) return
  if (!(await toast.confirm('确认删除该密码记录？该操作不可撤销。', '删除确认'))) return
  try {
    await store.remove(form.id)
    toast.success('已删除')
    emit('delete')
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  }
}
</script>

<style scoped lang="scss">
.password-row {
  display: flex;
  gap: 8px;
  width: 100%;
}
.password-row .el-input {
  flex: 1;
}
.form-actions {
  display: flex;
  gap: 8px;
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid #e5e5ea;
}
</style>
```

- [ ] **Step 2: 重写 `src/views/PasswordsView.vue`**

```vue
<template>
  <div class="passwords-view">
    <aside class="list-pane">
      <div class="list-header">
        <el-input v-model="keyword" placeholder="搜索平台或账号" :prefix-icon="Search" clearable size="small" />
        <el-select v-model="categoryFilter" size="small" class="cat-filter">
          <el-option label="全部分类" value="" />
          <el-option label="社交" value="social" />
          <el-option label="办公" value="office" />
          <el-option label="金融" value="finance" />
          <el-option label="自定义" value="custom" />
        </el-select>
        <el-button type="primary" size="small" @click="onNew">+ 新建密码</el-button>
      </div>
      <div class="password-list" v-loading="store.loading">
        <p v-if="!store.list.length" class="empty">还没有密码记录，点击「+ 新建密码」开始</p>
        <div
          v-for="p in filteredList"
          :key="p.id"
          class="password-item"
          :class="{ active: p.id === currentId }"
          @click="onSelect(p.id)"
        >
          <div class="item-main">
            <div class="platform">{{ p.platform }}</div>
            <div class="account">{{ p.account }}</div>
          </div>
          <div class="item-meta">
            <el-tag size="small" :type="categoryTagType(p.category)">{{ categoryLabel(p.category) }}</el-tag>
            <span v-if="p.typeText" class="type-text">{{ p.typeText }}</span>
          </div>
        </div>
      </div>
    </aside>

    <section class="form-pane">
      <PasswordForm
        v-if="store.current || mode === 'create'"
        :password="store.current"
        @saved="onSaved"
        @cancel="onCancel"
        @delete="onDeleted"
      />
      <EmptyState v-else emoji="👈" title="点击「+ 新建密码」或在左侧选择一条记录开始录入" hint="保存后，iOS 端走「局域网同步 → 下载」即可恢复到本地" />
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Search } from '@element-plus/icons-vue'
import PasswordForm from '@/components/PasswordForm.vue'
import EmptyState from '@/components/EmptyState.vue'
import { usePasswordsStore, passwordErrorMsg } from '@/stores/passwords'
import { useToast } from '@/composables/useToast'

const store = usePasswordsStore()
const toast = useToast()

const keyword = ref('')
const categoryFilter = ref('')
const currentId = ref<string | null>(null)
const mode = ref<'view' | 'create'>('view')

const filteredList = computed(() =>
  store.list.filter((p) => {
    const kw = keyword.value.trim().toLowerCase()
    const matchKw = !kw || p.platform.toLowerCase().includes(kw) || p.account.toLowerCase().includes(kw)
    const matchCat = !categoryFilter.value || p.category === categoryFilter.value
    return matchKw && matchCat
  })
)

onMounted(async () => {
  try {
    await store.fetchList()
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  }
})

function categoryLabel(v: string): string {
  return ({ social: '社交', office: '办公', finance: '金融', custom: '自定义' } as Record<string, string>)[v] || v
}

function categoryTagType(v: string): '' | 'success' | 'warning' | 'danger' | 'info' {
  return ({ social: '', office: 'success', finance: 'warning', custom: 'info' } as Record<string, '' | 'success' | 'warning' | 'danger' | 'info'>)[v] || ''
}

function onNew() {
  currentId.value = null
  store.clearCurrent()
  mode.value = 'create'
}

async function onSelect(id: string) {
  currentId.value = id
  mode.value = 'view'
  try {
    await store.fetchOne(id)
  } catch (err) {
    toast.showError(err, passwordErrorMsg(err))
  }
}

async function onSaved(id: string) {
  currentId.value = id
  mode.value = 'view'
  await store.fetchList()
  await store.fetchOne(id)
}

function onCancel() {
  store.clearCurrent()
  mode.value = 'view'
}

async function onDeleted() {
  currentId.value = null
  store.clearCurrent()
  mode.value = 'view'
  await store.fetchList()
}
</script>

<style scoped lang="scss">
.passwords-view {
  display: grid;
  grid-template-columns: 320px 1fr;
  gap: 16px;
  padding: 16px 24px;
  align-items: start;
}
@media (max-width: 960px) {
  .passwords-view {
    grid-template-columns: 1fr;
  }
}
.list-pane {
  position: sticky;
  top: 72px;
}
.list-header {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 12px;
}
.cat-filter {
  width: 100%;
}
.password-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.password-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  background: #fff;
  border: 1px solid #e5e5ea;
  border-radius: 8px;
  padding: 10px 12px;
  cursor: pointer;
  transition: border-color 0.15s, background 0.15s;
}
.password-item:hover {
  border-color: #007aff;
}
.password-item.active {
  background: #f0f8ff;
  border-color: #007aff;
}
.item-main {
  flex: 1;
  overflow: hidden;
}
.platform {
  font-weight: 500;
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.account {
  font-size: 12px;
  color: #8e8e93;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.item-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
  flex-shrink: 0;
}
.type-text {
  font-size: 11px;
  color: #aeaeb2;
}
.empty {
  color: #8e8e93;
  text-align: center;
  padding: 24px;
  font-size: 13px;
}
</style>
```

- [ ] **Step 3: dev 端到端验证**

启动 Go 服务 + `npm run dev`，访问 `http://localhost:5173/#/passwords`：
- 列表显示 Task 1 创建的密码记录
- 点「+ 新建密码」→ 表单出现 → 填写 → 点「生成随机」→ 密码框填入 12 位 → 保存 → 列表刷新
- 编辑现有记录 → 修改 → 保存
- 删除 → 二次确认 → 列表移除
- 搜索框输入关键字过滤；分类筛选切换

- [ ] **Step 4: 提交**

```bash
git add server/internal/web/files/src/
git commit -m "feat(web): implement password management page with random password generator"
```

---

## Task 10: web.go 改造 + 本地构建联调

**Files:**
- Modify: `server/internal/web/web.go`
- Modify: `server/internal/web/files/.gitignore`（确认 dist 排除）

**Interfaces:**
- Consumes: Task 2-9 完成的 Vue 工程（能 `npm run build` 生成 dist）
- Produces: Go 端 `//go:embed all:files/dist`，`go run ./cmd/server` 后访问 `http://localhost:8090/web` 看到完整应用

- [ ] **Step 1: 修改 `server/internal/web/web.go`**

```go
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
//     在 localStorage 维护，每次调 /api/* 时通过 fetch header 带上 X-Device-ID + X-Sync-Token。
//
// 注意：files/dist/ 是 Vite 构建产物，不入 git。本地开发需先 `cd internal/web/files && npm run build`。
func Register(r *gin.Engine) {
	sub, err := fs.Sub(distFS, "files/dist")
	if err != nil {
		// 仅在 //go:embed 指令写错时才会触发；编译期已保证 dist 目录存在
		panic("web embed: " + err.Error())
	}

	// /web → index.html
	r.GET("/web", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", indexHTML)
	})
	// /web/static/* → JS/CSS/图片
	r.StaticFS("/web/static", http.FS(sub))
}
```

- [ ] **Step 2: 确认 `server/internal/web/files/.gitignore` 排除 dist**

如果 Task 2 没创建或内容不全，确保包含：
```
node_modules/
dist/
.DS_Store
*.log
.vite/
```

- [ ] **Step 3: 构建 Vue + 启动 Go 服务**

```bash
# 终端 1：构建前端
cd server/internal/web/files
npm run build
ls dist/  # 确认有 index.html 和 assets/

# 终端 2：启动 Go 服务
cd server
SYNC_TOKEN=changeme MYSQL_DSN='root:root@tcp(127.0.0.1:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local' PORT=8090 go run ./cmd/server
```

浏览器访问 `http://localhost:8090/web`：
- 应看到完整的 Vue 应用（不是 hello world）
- 顶栏导航 4 项可切换
- 配置抽屉可唤起
- 菜谱/密码 CRUD 全流程可用（API 走同源 `/api/*`）

- [ ] **Step 4: 提交**

```bash
git add server/internal/web/web.go server/internal/web/files/.gitignore
git commit -m "feat(web): wire Go embed.FS to Vue dist, update web.go"
```

---

## Task 11: Dockerfile 调整 + 端到端验证

**Files:**
- Modify: `server/Dockerfile`
- Modify: `server/.dockerignore`（确保排除 node_modules / dist）

**Interfaces:**
- Consumes: Task 1-10 全部完成
- Produces: Docker 镜像构建通过，`docker compose up -d --build` 后访问 `http://<host>:8090/web` 完整可用

- [ ] **Step 1: 修改 `server/Dockerfile`**

在现有 builder 阶段前加 frontend 阶段：

```dockerfile
# ============================================================
# PersonalButler · Sync Server 多阶段 Dockerfile
# ============================================================
# 阶段 1：frontend（Vite 构建 Vue3 工程）
#   - 用 node:20-alpine 构建出 dist/ 静态资源
# 阶段 2：builder
#   - 用 golang:1.22-alpine 编译出静态二进制
#   - 把 frontend 阶段的 dist/ 拷到 embed 路径
#   - 开 CGO_ENABLED=0 + netgo 走纯 Go runtime
# 阶段 3：runtime
#   - gcr.io/distroless/static-debian12：~2MB，无 shell，攻击面最小
#   - 内嵌 web/files/dist/* 静态资源（embed.FS），无需额外挂卷
# ============================================================

# ---------- frontend builder (新增) ----------
FROM node:20-alpine AS frontend
WORKDIR /web
# 国内 npm 镜像加速
RUN npm config set registry https://registry.npmmirror.com
# 先拷依赖清单，利用 docker layer cache 加速 rebuild
COPY internal/web/files/package*.json ./
RUN npm ci
# 拷源码并构建
COPY internal/web/files/ ./
RUN npm run build  # 输出到 /web/dist

# ---------- backend builder ----------
FROM golang:1.22-alpine AS builder

WORKDIR /src

# 国内网络访问 proxy.golang.org / sum.golang.org 经常 i/o timeout
# 默认走 goproxy.cn；海外构建可通过 --build-arg GOPROXY=https://proxy.golang.org,direct 切回
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY}
ENV GOSUMDB=off

# 先拷依赖清单，利用 docker layer cache 加速 rebuild
COPY go.mod go.sum ./
RUN go mod download

# 拷源码（.dockerignore 已过滤掉本地构建产物 / .git 等）
COPY . .

# 把前端构建产物拷到 embed 路径
COPY --from=frontend /web/dist ./internal/web/files/dist

# 静态编译：CGO_ENABLED=0 + netgo 让二进制不依赖 glibc
# -ldflags="-s -w" 去掉调试信息，镜像更小
# -trimpath 移除构建机路径，方便排查问题
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/personal-butler-server \
    ./cmd/server

# ---------- runtime ----------
# distroless/static 不带 shell / 包管理器，最小攻击面；自带 /etc/ssl/certs 让
# 程序在需要时（虽然本服务只走内网 HTTP，但保留兼容性）也能验证 HTTPS 证书。
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

# 从 builder 拷贝编译好的二进制
COPY --from=builder /out/personal-butler-server /app/personal-butler-server

# 8090 是 iOS 客户端硬编码端口
EXPOSE 8090

# distroless 没有 shell，只能用 ENTRYPOINT + exec form
ENTRYPOINT ["/app/personal-butler-server"]
```

- [ ] **Step 2: 检查 `server/.dockerignore`**

确保包含（如果不存在则创建）：
```
.git
.gitignore
.env
*.md
deploy.sh
internal/web/files/node_modules
internal/web/files/dist
internal/web/files/.vite
```

注意：`internal/web/files/dist` 在本地构建产物会被排除，但 Docker 构建时会由 frontend 阶段重新生成并 COPY 进来。

- [ ] **Step 3: 本地 Docker 构建验证（可选，需要本地 docker）**

```bash
cd server
docker build -t personal-butler-server:test .
docker run --rm -p 8090:8090 \
  -e SYNC_TOKEN=changeme \
  -e MYSQL_DSN='root:root@tcp(host.docker.internal:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local' \
  personal-butler-server:test
```

浏览器访问 `http://localhost:8090/web`，应看到完整 Vue 应用。

如果本地无 Docker，跳过此步，依赖远程 `./deploy.sh <host> --init` 验证。

- [ ] **Step 4: 完整端到端验证清单**

启动服务后逐项验证：

1. 访问 `http://<host>:8090/web` 看到首页（自动唤起配置抽屉）
2. 配置 Device ID + Token → 测试连接成功
3. 菜谱 CRUD 全流程：新建 / 编辑 / 删除（含食材子项替换 / 图片上传）
4. 密码 CRUD 全流程：新建 / 编辑 / 删除 / 生成随机密码 / 显示切换
5. 首页统计数字与各业务页列表长度一致
6. Token 错误时显示「Sync Token 与服务端不一致」
7. iOS 端 download 后能拿到 Web 端录入的密码和菜谱（如果手头有 iOS 客户端）

- [ ] **Step 5: 提交**

```bash
git add server/Dockerfile server/.dockerignore
git commit -m "build(docker): add Node frontend build stage to Dockerfile"
```

---

## 自审记录

**Spec 覆盖检查：**
- §1-2 背景/技术栈 → Global Constraints
- §3 项目结构 → 文件结构总览 + 各 Task 的 Files
- §4 路由 → Task 5 Step 1
- §5 Pinia stores → Task 4
- §6 API 层 → Task 3
- §7.1 烹饪管理页 → Task 8
- §7.2 密码记录页 → Task 9
- §7.3 首页 → Task 7
- §7.4 配置页 → Task 6
- §8 后端 Password CRUD → Task 1
- §9 Dockerfile → Task 11
- §10 web.go → Task 10
- §10.1 本地开发流程 → Task 10 验证步骤
- §11 错误处理 → Task 3 (拦截器) + Task 6 (useToast)
- §11 测试策略 → 各 Task 的验证步骤
- §12 不在本次范围 → 无需任务
- §13 风险取舍 → 已在 Global Constraints 体现

**Placeholder 扫描：** 无 TBD / TODO / "implement later" 等；所有代码块均给出完整内容。

**类型一致性：**
- `RecipeInput` / `PasswordInput` 在 types 和 store / api / form 中签名一致
- `recipeApi` / `passwordApi` / `syncApi` 方法名在 api 层和 store 调用一致
- `useRecipesStore` / `usePasswordsStore` / `useOverviewStore` / `useConfigStore` 命名一致
- `recipeErrorMsg` / `passwordErrorMsg` 在 store 中定义，在 view 中调用

**已知简化（不算缺陷）：**
- Element-Plus 自动按需引入的 dts 文件（auto-imports.d.ts / components.d.ts）由 vite 插件运行时生成，vue-tsc 首次跑可能报缺文件；Task 2 Step 15 启动 dev 一次即可生成
- `useToast` 同时封装了 ElMessage 和 ElMessageBox，Task 6 的 confirm 方法返回 Promise<boolean>，便于 async/await 风格调用
