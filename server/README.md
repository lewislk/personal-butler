# PersonalButler · Sync Server

iOS 客户端「局域网 HTTP 全量同步」的服务端实现。技术栈：Go 1.22 + Gin + GORM + MySQL 8。

## 目录结构

```
server/
├── cmd/server/main.go              ← 入口
├── internal/
│   ├── config/                     ← 环境变量配置
│   ├── db/                         ← gorm 连接
│   ├── model/                      ← 表结构（(device_id, id) 复合主键）
│   ├── dto/                        ← 与 iOS SyncPayload 对齐的 JSON DTO
│   ├── middleware/                 ← X-Device-ID / X-Sync-Token 校验
│   ├── service/                    ← 业务：Upload/Download/Info/Clear
│   └── handler/                    ← Gin 路由
├── sql/init.sql                    ← MySQL 建库 & 建表
└── go.mod
```

## 快速开始

```bash
# 1. 初始化数据库
mysql -uroot -p < sql/init.sql

# 2. 启动服务
cd server
go mod tidy
SYNC_TOKEN=changeme \
MYSQL_DSN='root:root@tcp(127.0.0.1:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local' \
PORT=8090 \
go run ./cmd/server
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PORT` | `8090` | HTTP 监听端口（客户端硬编码 8090） |
| `SYNC_TOKEN` | 空 | 与请求头 `X-Sync-Token` 比对。空表示跳过 token 校验（仅限开发） |
| `MYSQL_DSN` | `root:root@tcp(127.0.0.1:3306)/personal_butler?...` | GORM DSN |

## API 契约

对齐 `docs/module-spec/module-backup-sync-spec.md`。

- 地址：`http://<host>:8090`
- 请求头：`Content-Type: application/json` · `X-Device-ID: <uuid>` · `X-Sync-Token: <shared>`
- 统一返回：`{ code: int, msg: string, data: T? }`

| Method | Path | 说明 |
|--------|------|------|
| POST | `/sync/upload` | body 是完整 `SyncPayload`，服务端按 `X-Device-ID` 做全量覆盖 |
| GET | `/sync/download` | 返回该 device 的完整 `SyncPayload` |
| GET | `/sync/info` | 返回该 device 的备份摘要（时间戳、条数） |
| DELETE | `/sync/clear` | 清空该 device 所有数据 |
| GET | `/healthz` | 健康检查（无鉴权） |

错误码：`0` 成功 / `1001` 头缺失 / `1002` 密钥错 / `1003` JSON 解析失败 / `2001` 存储失败 / `2002` 无备份 / `2003` 同设备写请求并发中 / `5000` 内部异常。

> **并发保护**：`/sync/upload` 与 `/sync/clear` 在服务端按 `X-Device-ID` 走进程内单飞锁（`sync.Map[deviceID]*sync.Mutex` + `TryLock`）。同一设备在上一次写事务未结束前再次发起 upload/clear，会立即回 `code=2003`，客户端应把按钮 disabled 并提示"上一次同步还在进行"。download / info 只读，不参与锁。

## 数据模型要点

- **多设备隔离**：所有业务表主键都是 `(device_id, id)`。同一台 iPhone 的多次上传彼此覆盖，两台设备互不影响。
- **全量覆盖语义**：`/sync/upload` 会先 `DELETE ... WHERE device_id = ?`，再批量 `INSERT`，整个过程在一个事务里。
- **敏感字段明文入库**：`password.password_plain` / `otp.secret_plain` 与客户端契约一致，仅限局域网使用；PRD 二期上 AES 后再迁移。
- **时间戳统一 DOUBLE**：与 Swift `TimeInterval` (unix seconds since 1970, `Double`) 对齐，避免时区与精度歧义。
- **schema 手动维护**：不启用 GORM `AutoMigrate`；改字段前请先改 `sql/init.sql` 并递增 `SyncMeta.dataVersion`。

### 当前 schema 版本（dataVersion = 4，对齐 iOS 端 `SyncPayload.swift`）

| 实体 | 表 | 关键字段（v4 新增 / 变更） |
|------|----|----------------------------|
| Todo | `todo` | v4 新增 `task_type` / `recipe_id` / `expected_ingredients` / `checked_ingredients`（NULL 表示未设置） |
| Food | `food` | v2 新增 `place_name` / `address` / `latitude` / `longitude`；v3 `rating` INT → DOUBLE，新增 `icon_image_base64` |
| CookRecipe | `cook_recipe` | v4 移除旧 `ingredients` 文本字段，新增 `ingredients_legacy_raw` / `icon_image_base64`；结构化食材拆到 `cook_ingredient` 子表 |
| CookIngredient | `cook_ingredient`（v4 新增） | 主键 `(device_id, id)`，`recipe_id` 关联同 device 下的 `cook_recipe.id`，不走外键约束 |
| CookCart | `cook_cart`（v4 新增） | 主键 `(device_id, id)`，`recipe_id` 关联同 device 下的 `cook_recipe.id` |

**升级提示**：本次 schema 与 v1 不兼容（旧 `cook_recipe.ingredients` 文本字段被移除，`food.rating` 类型变更），需要先 `DROP DATABASE personal_butler` 或手动 `mysql -uroot -p < sql/init.sql` 重建全部业务表。已有 v1 备份需用对应旧版服务端恢复，新服务端只接受 v4 payload。

## curl 自测

```bash
# 生成一个最小 payload（省略了业务字段）
cat > /tmp/payload.json <<'JSON'
{
  "syncMeta": {"deviceId":"dev-1","syncTimestamp":1700000000,"appVersion":"1.0.0","dataVersion":4},
  "data": {
    "todoList":[{"id":"t1","name":"测试","source":"manual","dueDate":null,"isDone":false,"createdAt":1700000000,"taskType":"none"}],
    "scheduleList":[], "anniversaryList":[], "passwordList":[], "otpList":[],
    "foodRecordList":[], "cookRecipeList":[], "cartList":[], "noteList":[], "appModuleList":[],
    "setting":{}
  }
}
JSON

curl -s -X POST http://127.0.0.1:8090/sync/upload \
  -H 'Content-Type: application/json' \
  -H 'X-Device-ID: dev-1' \
  -H 'X-Sync-Token: changeme' \
  --data-binary @/tmp/payload.json

curl -s http://127.0.0.1:8090/sync/download \
  -H 'X-Device-ID: dev-1' -H 'X-Sync-Token: changeme'

curl -s http://127.0.0.1:8090/sync/info \
  -H 'X-Device-ID: dev-1' -H 'X-Sync-Token: changeme'

curl -s -X DELETE http://127.0.0.1:8090/sync/clear \
  -H 'X-Device-ID: dev-1' -H 'X-Sync-Token: changeme'
```

## Web 表单录入

服务端在 `/web` 路径暴露一个嵌入式 HTML 表单（资源通过 `embed.FS` 打进二进制，零外部依赖），方便在电脑上录入菜谱等结构化数据，写入 DB 后 iOS 端走「局域网同步 → 下载」即可恢复到本地。

### 访问

```
http://<host>:8090/web
```

### 配置项

页面右上角「⚙️ 配置」按钮：

- **Device ID**：与 iOS 端 `AppSyncConfig.deviceID` 一致（从 iOS 端「我的 → 局域网同步」可看到前缀）
- **Sync Token**：与服务端 `SYNC_TOKEN` 环境变量一致

两项保存在浏览器 `localStorage`，下次访问自动回填。

### API

`/api/recipes/*` 共用 `/sync/*` 的 `X-Device-ID` + `X-Sync-Token` 鉴权头：

| Method | Path | 说明 |
|--------|------|------|
| GET | `/api/recipes` | 列出该 device 全部菜谱（含 ingredients） |
| GET | `/api/recipes/:id` | 取单条菜谱 |
| POST | `/api/recipes` | 新建菜谱 + 食材子项，返回 `{id}` |
| PUT | `/api/recipes/:id` | 全量更新菜谱 + 替换 ingredients |
| DELETE | `/api/recipes/:id` | 删除菜谱及其 ingredients |

每次写入都会 upsert `sync_meta` 行（`appVersion="web-form"`、`dataVersion=4`、`syncTimestamp=now`），保证 iOS 客户端即使从未 upload 过也能直接 download 到 Web 录入的数据。

### 推荐使用流程

1. iOS 端先做一次 **上传**，把本地状态推到服务端（避免之后 download 把本地数据覆盖丢失）
2. 浏览器打开 `/web`，配置 Device ID + Token
3. 录入 / 编辑菜谱，保存到 DB
4. iOS 端做 **下载** → restore：本地数据被服务端数据全量替换，包含 Web 新增的菜谱

> **注意**：iOS 端 upload 是全量覆盖语义（`DELETE WHERE device_id + INSERT`）。如果 iOS 在 Web 录入后再 upload，会**清空** Web 录入的数据。请严格遵循"先 iOS upload → 再 Web 编辑 → 再 iOS download"的顺序。
