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
│   ├── service/                    ← 业务：Upload/Download/Info/Clear + Recipe CRUD
│   ├── handler/                    ← Gin 路由
│   └── web/                        ← 嵌入式 HTML/CSS/JS（embed.FS）
├── sql/init.sql                    ← MySQL 建库 & 建表
├── Dockerfile                      ← 多阶段构建（builder + distroless runtime）
├── docker-compose.yml              ← 一键编排 mysql + server
├── deploy.sh                       ← 远程一键部署脚本（rsync + ssh）
├── .env.example                    ← 环境变量样例
└── go.mod
```

## 快速开始（Docker，推荐）

最快上手路径，无需在宿主机安装 Go / MySQL：

```bash
cd server
cp .env.example .env
# 修改 .env 中的 SYNC_TOKEN / MYSQL_ROOT_PASSWORD
docker compose up -d --build
```

启动完成后：

- API：`http://<host>:8090/sync/*` 与 `http://<host>:8090/api/*`
- Web 表单：`http://<host>:8090/web`
- 健康检查：`http://<host>:8090/healthz`

常用维护命令：

```bash
docker compose logs -f server          # 查日志
docker compose restart server         # 重启服务端（不动 mysql）
docker compose down                   # 停止并清理容器（保留数据卷）
docker compose down -v                # 连数据卷一起清掉（⚠️ 会丢数据，谨慎使用）
docker compose up -d --build server   # 仅重 build + 重启 server
```

> 首次启动会自动执行 `sql/init.sql` 建库建表；只要 `mysql_data` 卷还在，后续重启不会重复执行。

## 远程一键部署

`deploy.sh` 用 `rsync + ssh` 把 `server/` 同步到远程机器，再调用 `docker compose up -d --build` 拉起服务。本地（macOS）执行即可，无需在远程手动操作。

### 远程机器一次性准备（仅首次）

**1. 安装 Docker + Compose 插件**

```bash
# Ubuntu/Debian（远程机器上执行）
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER       # 让当前用户免 sudo 用 docker
newgrp docker                        # 立即生效，或重新 ssh 登录
```

CentOS / RHEL 用同一条 `curl -fsSL https://get.docker.com | sh` 即可。

**2. 开放 8090 端口（如启用了 ufw / firewalld）**

```bash
# Ubuntu (ufw)
sudo ufw allow 8090/tcp

# CentOS (firewalld)
sudo firewall-cmd --permanent --add-port=8090/tcp && sudo firewall-cmd --reload
```

云服务器（阿里云 / 腾讯云 / AWS 等）还需在**安全组**里放行 8090 入站。

**3. 配置免密 SSH 登录（强烈推荐）**

方式一：`ssh-copy-id` 推送公钥（最简单）

```bash
ssh-copy-id -p <端口> <user>@<host>
# 验证：ssh -p <端口> <user>@<host> 'docker version'  应该不需要密码且能看到 docker 版本
```

方式二：`~/.ssh/config` 别名（推荐，deploy.sh 原生支持）

把主机 / 用户 / 端口 / 密钥都写进 `~/.ssh/config`，之后 `ssh myserver` 即可免密登录，deploy.sh 也会自动读取这套配置。

```bash
# ~/.ssh/config
Host myserver
    HostName 192.168.1.10
    User root
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# 验证：ssh myserver 'docker version'  应该不需要密码且能看到 docker 版本
```

### 一键部署

在本地仓库 `server/` 目录下执行：

```bash
# 用 ~/.ssh/config 别名（推荐，端口/密钥全部自动读取）
./deploy.sh myserver --init

# 或传统的 user@host 形式（端口走 ~/.ssh/config 或默认 22）
./deploy.sh root@192.168.1.10 --init

# 后续更新代码：复用远程 .env，只 rebuild server 镜像
./deploy.sh myserver
```

可选环境变量：

| 变量 | 默认 | 说明 |
|------|------|------|
| `SSH_PORT` | 空 | SSH 端口。**留空时走 `~/.ssh/config`**（推荐密钥免密登录）；显式设置才用 `-p` 覆盖 |
| `REMOTE_DIR` | `~/personal-butler` | 远程部署目录 |
| `PB_SYNC_TOKEN` | 随机 16 字节 hex | 仅 `--init` 时生效，自定义 token |
| `PB_MYSQL_PASSWORD` | 随机 16 字节 hex | 仅 `--init` 时生效，自定义 MySQL 密码 |
| `PB_SERVER_PORT` | `8090` | 仅 `--init` 时写入 .env，影响端口映射 |

示例：

```bash
# 用 ~/.ssh/config 别名（端口/密钥/用户都从 config 读）
./deploy.sh myserver --init

# 自定义 SSH 端口（覆盖 config 中的 Port）
SSH_PORT=2222 ./deploy.sh deploy@host.example.com --init

# 自定义远程目录
REMOTE_DIR=/opt/personal-butler ./deploy.sh root@host

# 指定 token（避免随机生成）
PB_SYNC_TOKEN=my-secret-xxx ./deploy.sh root@host --init
```

部署成功后脚本会输出访问地址、iOS 同步地址、Web 表单地址；`--init` 模式还会在控制台打印一次随机生成的凭据（**仅展示一次，请妥善保存**）。

### 脚本工作流

1. **本地自检**：rsync / ssh 可用
2. **远程自检**：docker / docker compose 已安装
3. **创建远程目录**：`mkdir -p $REMOTE_DIR`
4. **rsync 同步源码**：`server/* → 远程`（排除 `.env` / 本地构建产物 / `.git` / IDE 文件 / `deploy.sh` 自身）
5. **生成 .env**（仅 `--init` 且远程不存在）：写入随机 `SYNC_TOKEN` / `MYSQL_ROOT_PASSWORD`
6. **远程构建并启动**：`docker compose up -d --build --remove-orphans`
7. **等待健康检查**：轮询 `http://127.0.0.1:8090/healthz`，30s 超时
8. **输出访问地址**：尝试取公网 IP，失败回退到内网 IP

### 常见问题

**Q: 部署完访问不了 8090？**
- 远程云服务器：检查**安全组**是否放行 8090 入站
- 自建机器：`sudo ufw status` / `sudo firewall-cmd --list-ports` 检查防火墙
- 容器是否真的起来了：`ssh <host> 'cd ~/personal-butler && docker compose ps'`

**Q: 远程 docker 提示 permission denied？**
- 当前 SSH 用户不在 docker 组：`sudo usermod -aG docker $USER && newgrp docker`
- 或重新 ssh 登录一次让组权限生效

**Q: 想换 token / MySQL 密码？**
- `ssh <host> 'rm ~/personal-butler/.env'`，再 `./deploy.sh <host> --init`
- 注意：换 MySQL 密码需要清掉 `mysql_data` 卷（会丢数据），生产慎用

**Q: 怎么查日志 / 重启？**

```bash
ssh <user>@<host>
cd ~/personal-butler
docker compose logs -f server       # 实时日志
docker compose restart server       # 重启 server（不动 mysql）
docker compose pull && docker compose up -d   # 拉最新 mysql 镜像
```

## 快速开始（本地源码运行）

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

Docker Compose 额外变量（见 `.env.example`）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MYSQL_ROOT_PASSWORD` | `mysql123` | MySQL root 密码；首次启动后改需清卷重建 |
| `MYSQL_DATABASE` | `personal_butler` | 数据库名（需与 `sql/init.sql` 一致） |
| `SERVER_PORT` | `8090` | 宿主机暴露端口 |

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

### 当前 schema 版本（dataVersion = 5，对齐 iOS 端 `SyncPayload.swift`）

| 实体 | 表 | 关键字段（最新变更） |
|------|----|----------------------------|
| Todo | `todo` | v4 新增 `task_type` / `recipe_id` / `expected_ingredients` / `checked_ingredients`（NULL 表示未设置） |
| Schedule | `schedule` | **v5 新增 `is_demo`**（TINYINT(1) NOT NULL DEFAULT 0） |
| Anniversary | `anniversary` | **v5 新增 `is_demo`** |
| Password | `password` | **v5 新增 `is_demo`** |
| OTP | `otp` | **v5 新增 `is_demo`** |
| Food | `food` | v2 新增 `place_name` / `address` / `latitude` / `longitude`；v3 `rating` INT → DOUBLE，新增 `icon_image_base64`；**v5 新增 `is_demo`** |
| CookRecipe | `cook_recipe` | v4 移除旧 `ingredients` 文本字段，新增 `ingredients_legacy_raw` / `icon_image_base64`；结构化食材拆到 `cook_ingredient` 子表；**v5 新增 `is_demo`** |
| CookIngredient | `cook_ingredient`（v4 新增） | 主键 `(device_id, id)`，`recipe_id` 关联同 device 下的 `cook_recipe.id`，不走外键约束 |
| CookCart | `cook_cart`（v4 新增） | 主键 `(device_id, id)`，`recipe_id` 关联同 device 下的 `cook_recipe.id` |
| Note | `note` | **v5 新增 `is_demo`** |

**v5 变更说明**：为支持 iOS 客户端「我的 → 清理Demo数据」按钮按需删除首启灌入的示例数据，对 `schedule` / `anniversary` / `password` / `otp` / `food` / `cook_recipe` / `note` 7 张表新增 `is_demo` 列。

- iOS 端 `SeedData` 灌入的示例数据 `is_demo=1`，用户自添数据 `is_demo=0`
- 服务端 DTO 对应字段为 `IsDemo *bool`（指针，对齐 iOS Optional；旧客户端不带此字段时为 `nil`，落库按 `false` 处理）
- Web 表单（`/api/recipes/*`）创建的菜谱 `is_demo=0`（用户自添语义）
- `cook_ingredient` / `cook_cart` / `todo` / `app_module` / `app_setting` 不参与 demo 清理，未加 `is_demo` 列

**升级提示**：v5 与 v1 不兼容（旧 `cook_recipe.ingredients` 文本字段被移除，`food.rating` 类型变更，且 7 张表新增 `is_demo` 列），需要先 `DROP DATABASE personal_butler` 或手动 `mysql -uroot -p < sql/init.sql` 重建全部业务表。已有 v1/v4 备份需用对应旧版服务端恢复，新服务端只接受 v5 payload。

## curl 自测

```bash
# 生成一个最小 payload（省略了业务字段）
cat > /tmp/payload.json <<'JSON'
{
  "syncMeta": {"deviceId":"dev-1","syncTimestamp":1700000000,"appVersion":"1.0.0","dataVersion":5},
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

每次写入都会 upsert `sync_meta` 行（`appVersion="web-form"`、`dataVersion=5`、`syncTimestamp=now`），保证 iOS 客户端即使从未 upload 过也能直接 download 到 Web 录入的数据。Web 表单创建的菜谱 `is_demo=0`（用户自添语义），不会被 iOS 端「清理Demo数据」按钮误删。

### 推荐使用流程

1. iOS 端先做一次 **上传**，把本地状态推到服务端（避免之后 download 把本地数据覆盖丢失）
2. 浏览器打开 `/web`，配置 Device ID + Token
3. 录入 / 编辑菜谱，保存到 DB
4. iOS 端做 **下载** → restore：本地数据被服务端数据全量替换，包含 Web 新增的菜谱

> **注意**：iOS 端 upload 是全量覆盖语义（`DELETE WHERE device_id + INSERT`）。如果 iOS 在 Web 录入后再 upload，会**清空** Web 录入的数据。请严格遵循"先 iOS upload → 再 Web 编辑 → 再 iOS download"的顺序。
