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

## curl 自测

```bash
# 生成一个最小 payload（省略了业务字段）
cat > /tmp/payload.json <<'JSON'
{
  "syncMeta": {"deviceId":"dev-1","syncTimestamp":1700000000,"appVersion":"1.0.0","dataVersion":1},
  "data": {
    "todoList":[{"id":"t1","name":"测试","source":"manual","dueDate":null,"isDone":false,"createdAt":1700000000}],
    "scheduleList":[], "anniversaryList":[], "passwordList":[], "otpList":[],
    "foodRecordList":[], "cookRecipeList":[], "noteList":[], "appModuleList":[],
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
