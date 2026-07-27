# Web 后台录入重构设计

**日期：** 2026-07-27
**范围：** `server/internal/web` 全量重构 + 后端新增 Password CRUD
**目标：** 用 Vite + Vue3 + TypeScript + Element-Plus 重构现有零依赖 HTML/JS 三件套，完善「烹饪管理」和「密码记录」两个页面的后台录入能力

---

## 1. 背景与现状

### 1.1 现状

`server/internal/web/files/` 目前是零依赖的原生 HTML + JS + CSS 三件套，仅提供「菜谱录入」一个页面：

- `index.html` / `app.js` / `style.css` 三件套
- 后端已有 `/api/recipes/*` 5 个 CRUD 端点（`server/internal/handler/recipe.go` + `service/recipe.go`）
- 静态资源通过 Go `embed.FS` 嵌入二进制，部署时只有一个可执行文件
- 鉴权复用 `/sync/*` 的 `X-Device-ID` + `X-Sync-Token` 头

### 1.2 痛点

1. 只有菜谱一个页面，密码记录无法在 Web 端录入
2. 原生 JS 维护成本高，缺乏类型检查和组件复用
3. 后端缺少 `/api/passwords/*` 单条 CRUD 端点，密码只能走 `/sync/*` 全量覆盖语义

### 1.3 用户确认的边界

- 后端：新增 `/api/passwords/*` CRUD（参照 recipe 模式），OTP 不在 Web 端管理
- 密码页：只录密码，不含 OTP（与 iOS PasswordView 双 Tab 不同）
- 构建：Vite 构建到 `server/internal/web/files/dist/`，Go `embed.FS` 嵌入，Dockerfile 加 Node 阶段
- 路由：首页总览 + 烹饪管理 + 密码记录 + 配置页

---

## 2. 技术栈

| 项 | 选型 | 版本 |
|----|------|------|
| 构建工具 | Vite | 5.x |
| 框架 | Vue 3 + TypeScript | 3.4.x / 5.x |
| 路由 | vue-router | 4.x（hash 模式） |
| 状态管理 | Pinia | 2.x |
| 请求 | Axios | 1.x |
| UI 组件 | Element-Plus | 2.x（unplugin-vue-components 自动按需引入） |
| 样式 | SCSS | 与 Element-Plus 主题变量覆盖配合 |
| 代码校验 | ESLint + Prettier | eslint-plugin-vue + @typescript-eslint |

---

## 3. 项目结构

```
server/internal/web/
├── web.go                         ← Go 端 embed.FS 入口（修改：嵌入 files/dist/）
└── files/                         ← Vue 工程目录（替换原三件套）
    ├── package.json
    ├── vite.config.ts
    ├── tsconfig.json
    ├── .eslintrc.cjs
    ├── .prettierrc.json
    ├── index.html                 ← Vite 入口 HTML
    ├── src/
    │   ├── main.ts                ← createApp + Pinia + Router 注册
    │   ├── App.vue                ← 顶层布局（AppHeader + RouterView + 全局 ConfigDrawer）
    │   ├── router/index.ts        ← vue-router 4，hash 模式，4 个路由
    │   ├── stores/
    │   │   ├── config.ts          ← Device ID / Token，持久化到 localStorage
    │   │   ├── recipes.ts         ← 菜谱列表 + CRUD
    │   │   ├── passwords.ts       ← 密码列表 + CRUD
    │   │   └── overview.ts        ← 首页统计
    │   ├── api/
    │   │   ├── http.ts            ← axios 实例 + 请求/响应拦截器
    │   │   ├── recipes.ts         ← 菜谱 CRUD API
    │   │   ├── passwords.ts       ← 密码 CRUD API
    │   │   └── sync.ts            ← getSyncInfo（首页用）
    │   ├── views/
    │   │   ├── HomeView.vue       ← 首页总览
    │   │   ├── RecipesView.vue    ← 烹饪管理
    │   │   ├── PasswordsView.vue  ← 密码记录
    │   │   └── SettingsView.vue   ← 配置页
    │   ├── components/
    │   │   ├── AppHeader.vue      ← 顶栏（标题 + 导航 + 配置入口）
    │   │   ├── ConfigDrawer.vue   ← 全局配置抽屉
    │   │   ├── EmptyState.vue     ← 空状态占位
    │   │   ├── RecipeForm.vue     ← 菜谱表单
    │   │   ├── IngredientEditor.vue ← 食材行编辑器
    │   │   ├── PasswordForm.vue   ← 密码表单
    │   │   └── ImagePicker.vue    ← 图片选择（512px JPEG 0.7 压缩）
    │   ├── composables/
    │   │   ├── useImageCompress.ts ← 封装 fileToBase64 逻辑
    │   │   └── useToast.ts        ← 封装 ElMessage 的统一调用
    │   ├── types/
    │   │   ├── recipe.ts          ← Recipe / RecipeIngredient 接口
    │   │   ├── password.ts        ← Password 接口
    │   │   └── api.ts             ← APIResponse<T> 泛型 + ApiError + 错误码常量
    │   ├── styles/
    │   │   ├── variables.scss     ← 覆盖 Element-Plus 主题变量（primary=#007aff）
    │   │   └── global.scss        ← 全局重置 + 通用工具类
    │   └── env.d.ts               ← Vite 环境变量类型声明
    └── dist/                      ← Vite 构建输出（gitignore，Docker 构建期生成）
```

**关键约定：**

- `files/` 目录直接放 Vue 工程，旧三件套（index.html/app.js/style.css）会被 Vite 工程覆盖
- `dist/` 不进 git（`.gitignore` 排除），由 Docker 构建期 `npm run build` 生成；本地开发也可 `npm run build` 后 `go run`
- Go 端 `web.go` 改为 `//go:embed all:files/dist`，把整个 dist 嵌入

---

## 4. 路由设计

### 4.1 路由表

```ts
// src/router/index.ts
const routes = [
  { path: '/',           name: 'home',      component: () => import('@/views/HomeView.vue'),      meta: { title: '总览' } },
  { path: '/recipes',    name: 'recipes',   component: () => import('@/views/RecipesView.vue'),  meta: { title: '烹饪管理' } },
  { path: '/passwords',  name: 'passwords', component: () => import('@/views/PasswordsView.vue'),meta: { title: '密码记录' } },
  { path: '/settings',   name: 'settings',  component: () => import('@/views/SettingsView.vue'), meta: { title: '配置' } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({
  history: createWebHashHistory(),  // hash 模式，URL 形如 /web#/recipes
  routes,
})
```

### 4.2 选择 Hash 路由的理由

- **零后端改动**：Go 端继续 `r.GET("/web", ...)` 返回 index.html，`/web/static/*` 服务静态资源，无需新增 fallback
- 浏览器刷新 `/web#/passwords` 时只会请求 `/web`，不会触发 404
- embed.FS 部署模式保持不变

### 4.3 导航布局

- 顶栏 `AppHeader.vue` 固定顶部，左侧 Logo + 当前页面标题，右侧 `el-menu` 横向导航（总览/烹饪/密码/配置）
- 移动端折叠为 `el-dropdown`
- 配置抽屉 `ConfigDrawer.vue` 全局挂在 `App.vue`，从任意页面点击顶栏 ⚙️ 都能唤起；`/settings` 路由是同一份配置的独立路由版（便于书签直达）

### 4.4 Go 端路由（保持不变）

- `GET /web` → 返回 `index.html`（dist 根）
- `GET /web/static/*` → 服务 dist 下的 JS/CSS/图片
- `GET /api/recipes/*` → 现有菜谱 CRUD（共用 AuthHeader middleware）
- `GET /api/passwords/*` → 新增密码 CRUD（共用 AuthHeader middleware）

---

## 5. 状态管理（Pinia）

4 个独立 store，每个职责单一。store 不持久化业务数据（recipes/passwords），只在内存；刷新页面重新 fetch。仅 `config` store 持久化到 localStorage。

### 5.1 config store

```ts
// 持久化字段
deviceId: string      // 与 iOS AppSyncConfig.deviceID 一致
syncToken: string     // 与服务端 SYNC_TOKEN 一致

// actions
loadFromLocalStorage() / saveToLocalStorage()
clear()  // 退出登录语义
isConfigured: ComputedRef<boolean>  // deviceId 非空
```

### 5.2 recipes store

```ts
list: Recipe[]           // 列表（不含 ingredients 详情）
current: Recipe | null   // 当前编辑的菜谱详情
loading: boolean

// actions
fetchList()
fetchOne(id)
create(input)
update(id, input)
remove(id)
```

### 5.3 passwords store

```ts
list: Password[]
current: Password | null
loading: boolean

// actions
fetchList()
fetchOne(id)
create(input)
update(id, input)
remove(id)
```

### 5.4 overview store

```ts
info: SyncInfo | null    // 来自 GET /sync/info
recipeCount: number      // 来自 recipes.list.length
passwordCount: number

// actions
refresh()  // 并行调 fetchList + getInfo
```

---

## 6. API 层

### 6.1 axios 实例 + 拦截器

```ts
// src/api/http.ts
const http = axios.create({ baseURL: '', timeout: 15000 })

// 请求拦截：注入鉴权头
http.interceptors.request.use((config) => {
  const cfg = useConfigStore()
  if (!cfg.deviceId) {
    return Promise.reject(new ApiError(1001, '请先在配置中填写 Device ID'))
  }
  config.headers['X-Device-ID'] = cfg.deviceId
  config.headers['X-Sync-Token'] = cfg.syncToken || ''
  config.headers['Content-Type'] = 'application/json'
  return config
})

// 响应拦截：拆 APIResponse，code !== 0 转 ApiError
http.interceptors.response.use(
  (resp) => {
    const body = resp.data as APIResponse<unknown>
    if (body.code !== 0) {
      throw new ApiError(body.code, body.msg || `code=${body.code}`)
    }
    return body.data  // 业务层直接拿 data
  },
  (err) => {
    if (err instanceof AxiosError) {
      throw new ApiError(-1, err.message)
    }
    throw err
  }
)
```

### 6.2 错误码集中映射

```ts
// src/types/api.ts
export const ErrorCode = {
  OK: 0,
  HEADER_MISSING: 1001,   // → 自动唤起 ConfigDrawer
  TOKEN_INVALID: 1002,    // → 提示「Sync Token 与服务端不一致」
  JSON_PARSE_ERROR: 1003,
  STORE_FAILED: 2001,
  NO_BACKUP: 2002,        // → 首页显示「尚未同步」
  SYNC_IN_PROGRESS: 2003, // → 按钮禁用 + 重试提示
  INTERNAL: 5000,
} as const
```

### 6.3 业务 API 文件

```ts
// src/api/recipes.ts
export const recipeApi = {
  list: () => http.get<Recipe[]>('/api/recipes'),
  get: (id: string) => http.get<Recipe>(`/api/recipes/${encodeURIComponent(id)}`),
  create: (input: RecipeInput) => http.post<{ id: string }>('/api/recipes', input),
  update: (id: string, input: RecipeInput) => http.put<void>(`/api/recipes/${encodeURIComponent(id)}`, input),
  remove: (id: string) => http.delete<void>(`/api/recipes/${encodeURIComponent(id)}`),
}
```

```ts
// src/api/passwords.ts（与后端新增的 /api/passwords/* 对齐）
export const passwordApi = {
  list: () => http.get<Password[]>('/api/passwords'),
  get: (id: string) => http.get<Password>(`/api/passwords/${encodeURIComponent(id)}`),
  create: (input: PasswordInput) => http.post<{ id: string }>('/api/passwords', input),
  update: (id: string, input: PasswordInput) => http.put<void>(`/api/passwords/${encodeURIComponent(id)}`, input),
  remove: (id: string) => http.delete<void>(`/api/passwords/${encodeURIComponent(id)}`),
}
```

---

## 7. 业务页面

### 7.1 烹饪管理页（迁移现有功能）

**布局：** 左侧列表 + 右侧表单（沿用现有 `320px + 1fr` 双栏）

**列表区：**
- 顶部搜索框（`el-input` 带前缀图标，按名称模糊过滤）
- 分类筛选（`el-select`：全部/家常菜/面食/汤羹/甜品）
- 菜谱卡片：emoji + 名称 + 分钟·难度 标签
- 底部「+ 新建」`el-button`

**表单区（`RecipeForm.vue`）：**
- 名称、emoji（maxlength=8）、难度（`el-select`）、分钟（`el-input-number`）、分类（`el-select`）
- 图片图标：`ImagePicker.vue` 组件，512px JPEG 0.7 压缩（迁移现有 canvas 逻辑到 `useImageCompress.ts`）
- 食材子项：`IngredientEditor.vue`，每行 名称/用量/顺序 + 删除按钮，底部「+ 添加食材」
- 步骤、小贴士：`el-input type=textarea`
- 旧版食材文本：折叠面板内（默认收起，提示「兼容字段，新数据请用上方食材列表」）
- 底部操作：保存（`el-button type=primary`）/ 取消 / 删除（编辑态显示，`el-button type=danger` + `ElMessageBox.confirm`）

**交互：**
- 列表项点击 → 调 `recipes.fetchOne(id)` → 表单回填
- 保存成功 → `ElMessage.success` + 刷新列表 + 重新加载该条详情
- 删除前 `ElMessageBox.confirm('确认删除该菜谱？该操作不可撤销。', '删除确认', { type: 'warning' })`

### 7.2 密码记录页（新增）

**布局：** 与烹饪页对称，左侧列表 + 右侧表单

**列表区：**
- 顶部搜索框（按 platform / account 模糊过滤）
- 分类筛选（`el-select`：全部/社交/办公/金融/自定义）
- 密码卡片：platform（标题）+ account（副标题）+ typeText（辅文）+ 分类 Tag
- 底部「+ 新建密码」

**表单区（`PasswordForm.vue`）：**
- 平台名称（platform）`el-input`，必填
- 账号（account）`el-input`，必填
- 密码明文（passwordPlain）`el-input type=password` + 显示/隐藏切换图标（`el-icon` View/Hide）+ 「生成随机密码」按钮（12 位大小写+数字+符号）
- 分类（category）`el-select`：社交/办公/金融/自定义
- 展示辅文（typeText）`el-input`，可选，placeholder「例如：社交 · 常用」
- 底部操作：保存 / 取消 / 删除

**关键交互：**
- 进入页面**不触发生物识别**（与 iOS 不同，Web 端通过 Device ID + Token 已是局域网内可信环境）
- 密码明文默认隐藏（`show-password` 属性）；点击眼睛图标切换显示
- 「生成随机密码」：调 `crypto.getRandomValues` 生成 12 位（大写+小写+数字+特殊符号各 3 位）
- 保存成功 → 列表刷新 + 切到详情态
- 删除前 `ElMessageBox.confirm('确认删除该密码记录？该操作不可撤销。')`

**字段对齐 iOS `PasswordAccount`：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| platform | string | 是 | 平台名称 |
| account | string | 是 | 账号 |
| passwordPlain | string | 是 | 密码明文 |
| category | string | 否，默认 `social` | social/office/finance/custom |
| typeText | string | 否 | 展示辅文 |
| updatedAt | number | 服务端生成 | unix timestamp |

### 7.3 首页总览

**卡片式仪表盘布局（`el-row` + `el-col`，PC 三列、移动端单列）：**

- **同步状态卡片**：显示 `/sync/info` 返回的 `syncTimestamp`（格式化为本地时间）、`appVersion`、`dataVersion`、`totalCount`；未配置 Device ID 时显示「请先配置」+ 跳转按钮
- **菜谱卡片**：菜谱总数 + 「立即管理」按钮 → 跳 `/recipes`
- **密码卡片**：密码总数 + 「立即管理」按钮 → 跳 `/passwords`
- **使用提示卡片**：折叠面板，说明「iOS 上传 → Web 编辑 → iOS 下载」顺序，警告 upload 会覆盖

**数据加载：** `onMounted` 调 `overview.refresh()`，并行 fetch 三个数据源；任一失败不影响其他卡片展示（独立 try-catch）

### 7.4 配置页

**两种入口指向同一份配置数据：**
- 顶栏 ⚙️ → 全局 `ConfigDrawer`（`el-drawer` 从右侧滑出，任何页面可唤起）
- `/settings` 路由 → `SettingsView.vue`（独立页面版，便于书签直达）

**字段：**
- Device ID（`el-input`，placeholder「例如：8F5B2A3C-...」）
- Sync Token（`el-input type=password` + 显示切换）
- 「测试连接」按钮：调 `GET /sync/info`，成功显示同步信息摘要，失败显示具体错误码对应的中文提示
- 「保存」按钮：写入 `config` store + localStorage + `ElMessage.success`
- 「清空配置」按钮：清空 localStorage + store，`ElMessageBox.confirm` 二次确认

**自动行为：**
- 进入任意页面时，若 `config.deviceId` 为空 → 自动唤起 `ConfigDrawer` + `ElMessage.warning('请先配置 Device ID')`
- API 收到 `code=1001` → 全局响应拦截器自动唤起 `ConfigDrawer`

---

## 8. 后端新增 Password CRUD

完全复制 `recipe.go` 的模式，新增 3 个文件。

### 8.1 `server/internal/service/password.go`

```go
type PasswordService struct { db *gorm.DB }

type PasswordInput struct {
    ID            *string `json:"id,omitempty"`           // POST 留空；PUT 必填且与 path 一致
    Platform      string  `json:"platform"`                // 必填
    Account       string  `json:"account"`                 // 必填
    PasswordPlain string  `json:"passwordPlain"`           // 必填
    TypeText      string  `json:"typeText"`
    Category      string  `json:"category"`                // 默认 "social"
}

// 与 RecipeService 一致的 5 个方法：List / Get / Create / Update / Delete
// 每次写入后调 upsertSyncMeta(tx, deviceID) 确保 iOS 端能 download
// 字段对齐 model.Password + dto.SyncPasswordDTO
// 注意：passwordPlain 是明文，不脱敏直接存（与 sync.go upload 全量语义一致）
```

**关键约定：**
- 主键 `(device_id, id)`，与现有所有业务表一致
- `id` 由服务端用 `crypto/rand` 生成 v4 UUID（复用 `recipe.go` 已有的 `newUUID()` 函数，不抽公共文件，password.go 直接调用同包内函数）
- 每次写入后调 `upsertSyncMeta(tx, deviceID)`（复用 recipe.go 已有函数，不重写）
- `Category` 是 `PasswordInput` 的必填字段，前端表单默认送 `"social"`；后端在 `Create` / `Update` 时兜底：若 `Category == ""` 则写入 `"social"`（与 iOS `PasswordCategory` 默认值一致）
- Web 表单创建的密码 `is_demo=0`（用户自添语义），不会被 iOS 端「清理Demo数据」按钮误删

### 8.2 `server/internal/handler/password.go`

```go
type PasswordHandler struct { svc *service.PasswordService }

func (h *PasswordHandler) Register(rg *gin.RouterGroup) {
    rg.GET("/passwords", h.List)
    rg.POST("/passwords", h.Create)
    rg.GET("/passwords/:id", h.Get)
    rg.PUT("/passwords/:id", h.Update)
    rg.DELETE("/passwords/:id", h.Delete)
}
// 校验逻辑与 recipe.go 一致：platform 必填 → 1003；not found → 2002
```

### 8.3 `server/cmd/server/main.go` 改动

```go
// 新增 3 行（与 recipe 注册对称）
passwordSvc := service.NewPasswordService(gdb)
passwordH := handler.NewPasswordHandler(passwordSvc)
passwordH.Register(api)  // 挂到已有的 /api 组（共用 AuthHeader middleware）
```

### 8.4 不修改的文件

- `model.Password`（表已存在，schema 无变化）
- `dto.SyncPasswordDTO`（DTO 已对齐）
- `sql/init.sql`（password 表已存在）

---

## 9. Dockerfile 调整

在现有 backend builder 阶段前加一个 Node 构建阶段：

```dockerfile
# ---------- frontend builder (新增) ----------
FROM node:20-alpine AS frontend
WORKDIR /web
COPY internal/web/files/package*.json ./
RUN npm ci --registry=https://registry.npmmirror.com
COPY internal/web/files/ ./
RUN npm run build  # 输出到 /web/dist

# ---------- backend builder (修改) ----------
FROM golang:1.22-alpine AS builder
WORKDIR /src
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY} GOSUMDB=off
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# 把前端构建产物拷到 embed 路径
COPY --from=frontend /web/dist ./internal/web/files/dist
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/personal-butler-server ./cmd/server
```

runtime 阶段保持不变（distroless/static + 二进制 + EXPOSE 8090）。

---

## 10. `web.go` 改动

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

func Register(r *gin.Engine) {
    sub, err := fs.Sub(distFS, "files/dist")
    if err != nil {
        panic("web embed: " + err.Error())
    }

    r.GET("/web", func(c *gin.Context) {
        c.Data(http.StatusOK, "text/html; charset=utf-8", indexHTML)
    })
    r.StaticFS("/web/static", http.FS(sub))
}
```

**注意：** 旧的 `//go:embed files/index.html` 改为 `//go:embed files/dist/index.html`，旧的 `files/index.html` / `app.js` / `style.css` 三件套会被 Vite 工程覆盖删除。

### 10.1 本地开发流程（embed 编译依赖）

`//go:embed files/dist/...` 要求编译期 `files/dist/` 目录必须存在且非空，否则 `go build` 直接失败。`dist/` 不进 git，因此本地开发有两种工作流：

**工作流 A：纯前端开发（推荐）**
```bash
cd server/internal/web/files
npm install
npm run dev   # Vite dev server，端口 5173，配 proxy 代理 /api 到 http://localhost:8090
```
- 不需要 Go 端运行，前端独立调试
- `vite.config.ts` 配 `server.proxy: { '/api': 'http://localhost:8090', '/sync': 'http://localhost:8090' }`
- 适合纯 UI 调整、表单交互验证

**工作流 B：联调后端**
```bash
# 终端 1：启动 Go 服务（需要先构建一次 dist 让 embed 编译通过）
cd server/internal/web/files && npm run build
cd server && go run ./cmd/server

# 终端 2（可选）：前端热更新
cd server/internal/web/files && npm run dev
```
- 浏览器访问 `http://localhost:8090/web`（用 Go 服务的 embed 产物）
- 或访问 `http://localhost:5173`（用 Vite dev server，API 走 proxy）
- 适合验证 Go 端 embed 路径、生产构建行为

**首次构建兜底：** `files/dist/` 不存在时，运行 `cd server/internal/web/files && npm run build` 生成；不要手动创建空目录骗过编译，否则运行时 `fs.Sub` 会 panic。

---

## 11. 错误处理与测试策略

### 11.1 错误处理

- **API 层**：axios 响应拦截器统一把 `code !== 0` 转为 `ApiError`，业务层 try-catch 拿到 `err.code` 后做差异化处理
- **全局错误码映射**（`useToast.ts`）：
  - `1001` → 「请先配置 Device ID」+ 自动唤起 ConfigDrawer
  - `1002` → 「Sync Token 与服务端不一致，请检查配置」
  - `2002` → 「尚无备份数据」(首页显示，业务页不报错)
  - `2003` → 「操作进行中，请稍后重试」+ 按钮 disabled 3s
  - `5000` / 网络错误 → 「服务异常，请稍后重试」
- **业务层**：每个 action 包 try-catch，错误统一通过 `ElMessage.error` 显示，loading 状态在 finally 里复位

### 11.2 测试策略

- **不写单元测试**（MVP 阶段，与 iOS 端约定一致）
- **手动验证清单：**
  1. `npm run dev` 启动 Vite dev server，配 proxy 代理 `/api` 到本地 Go 服务，验证 4 个页面交互
  2. `npm run build` 后 `go run ./cmd/server`，访问 `http://localhost:8090/web` 验证生产构建
  3. 未配置 Device ID 时所有页面正确提示 + 自动唤起配置抽屉
  4. 菜谱 CRUD 全流程：新建/编辑/删除（含食材子项替换）/图片上传
  5. 密码 CRUD 全流程：新建/编辑/删除/生成随机密码/显示切换
  6. 首页统计数字与各业务页列表长度一致
  7. Token 错误时显示「Sync Token 与服务端不一致」
  8. iOS 端 download 后能拿到 Web 端录入的密码和菜谱

---

## 12. 不在本次范围

明确不做的事：

- OTP（2FA）的 Web 端录入（保持 iOS 端扫码录入）
- 其他业务模块（Todo/Schedule/Anniversary/Food/Note）的 Web 端录入
- 密码字段的 AES 加密（与现有 sync.go 全量上传一致，明文入库，PRD 二期统一迁移）
- 国际化（继续简体中文 UI）
- 暗色模式（Element-Plus 默认浅色主题即可）
- 单元测试 / E2E 测试（MVP 阶段不写）
- Web 端的生物识别（局域网内通过 Device ID + Token 鉴权，不需要）

---

## 13. 风险与已知取舍

| 风险 | 取舍 |
|------|------|
| 密码明文经局域网传输 | 与现有 sync.go 全量上传语义一致；PRD 二期统一上 AES 后再迁移 |
| Vite 构建增加 Docker 镜像构建时间 | node:20-alpine + npm ci 缓存友好，预计增加 30~60s；可接受 |
| Hash 路由 URL 不美观 | 零后端改动，部署简单；MVP 阶段优先稳定 |
| 旧三件套被覆盖 | 用户已确认重构；旧代码可在 git 历史中追溯 |
| store 不持久化业务数据 | 刷新页面重新 fetch，避免本地与服务端状态不一致；与现有 app.js 行为一致 |

---

## 14. 后续演进

本次重构后，未来扩展新模块（如 Todo / Note 的 Web 端录入）只需：

1. 后端新增 `service/xxx.go` + `handler/xxx.go` + `main.go` 注册（复制 password 模式）
2. 前端新增 `api/xxx.ts` + `stores/xxx.ts` + `views/XxxView.vue`
3. 路由表加一行
4. 顶栏导航加一项

无需改动核心架构。
