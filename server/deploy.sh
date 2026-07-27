#!/usr/bin/env bash
# ============================================================
# PersonalButler · 远程一键部署脚本
# ============================================================
# 用法：
#   ./deploy.sh user@host                       # 默认参数部署
#   ./deploy.sh myserver                        # 使用 ~/.ssh/config 中配置的别名（免密/端口/密钥自动读取）
#   ./deploy.sh user@host --init               # 首次部署：远程生成 .env（默认内置 mysql 模式）
#   SSH_PORT=2222 ./deploy.sh user@host         # 自定义 SSH 端口（不设则走 ~/.ssh/config）
#   REMOTE_DIR=/opt/pb ./deploy.sh user@host    # 自定义远程目录
#   PB_SYNC_TOKEN=xxx ./deploy.sh user@host    # 直接传入 token（不交互）
#
# MySQL 部署模式（仅 --init 时生效，写入 .env 后续部署复用）：
#   PB_USE_BUILTIN_MYSQL=1（默认）  内置 mysql：compose 拉起 mysql 容器，自动建库建表
#   PB_USE_BUILTIN_MYSQL=0          外置 mysql：用户已自行装好 mysql，compose 只起 server
#                                   必须同时传 PB_MYSQL_DSN 指向已安装的 mysql 实例
#
#   # 内置 mysql（最简上手）
#   ./deploy.sh myserver --init
#
#   # 外置 mysql（用户已有 mysql）
#   PB_USE_BUILTIN_MYSQL=0 \
#   PB_MYSQL_DSN='root:xxx@tcp(192.168.1.20:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local' \
#   ./deploy.sh myserver --init
#
# SSH 连接说明：
#   - 不显式设置 SSH_PORT 时，脚本不会传 -p，ssh / rsync 会自动读取 ~/.ssh/config
#     （Host / HostName / User / Port / IdentityFile 等都生效），适合密钥免密登录。
#   - 显式 SSH_PORT=2222 时，会强制用 -p 2222 覆盖配置中的端口。
#
# 工作流（本地执行 → 远程执行）：
#   1. 本地：rsync 同步 server/* 到远程 REMOTE_DIR（排除本地 .env / 构建产物）
#   2. 远程：若 --init 且 .env 不存在，生成一份带随机密码的 .env
#   3. 远程：docker compose pull mysql + docker compose up -d --build server
#   4. 远程：等待 /healthz 返回 200，输出访问地址
#
# 远程机器前置条件：
#   - rsync 已安装（脚本会自检，rsync 同步源码用）
#   - docker / docker compose 已安装（脚本会自检）
#   - 当前 SSH 用户能免密执行 docker（或在 sudo 组）
#   - 端口 8090 未被占用
# ============================================================

set -euo pipefail

# ---------- 颜色输出 ----------
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
NC=$'\033[0m'
log()  { printf "${BLUE}[%s]${NC} %s\n" "$(date +%H:%M:%S)" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
die()  { printf "${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

# ---------- 参数解析 ----------
SSH_HOST="${1:-}"
shift || true
INIT_MODE=0
for arg in "$@"; do
  case "$arg" in
    --init|-i) INIT_MODE=1 ;;
    *) die "未知参数：$arg" ;;
  esac
done

[[ -n "$SSH_HOST" ]] || die "用法：$0 <user@host | ssh别名> [--init]
示例：
  $0 root@192.168.1.10 --init
  $0 myserver              # myserver 是 ~/.ssh/config 中的别名
  SSH_PORT=2222 $0 deploy@host"

# SSH_PORT 留空=走 ~/.ssh/config（推荐密钥免密登录）；显式设置才传 -p 覆盖
SSH_PORT="${SSH_PORT:-}"
RSYNC_SSH="ssh"
[[ -n "$SSH_PORT" ]] && RSYNC_SSH="ssh -p $SSH_PORT"
# 提示命令用的 ssh 前缀（含端口），供 echo 输出
SSH_CMD_PREFIX="ssh"
[[ -n "$SSH_PORT" ]] && SSH_CMD_PREFIX="ssh -p $SSH_PORT"
REMOTE_DIR="${REMOTE_DIR:-~/personal-butler}"

# 封装 ssh：自动带端口（若设置），其余参数透传
# 避免在 set -u 下使用空数组 "${SSH_PORT_ARG[@]}"（macOS bash 3.2 会报 unbound variable）
pb_ssh() {
  if [[ -n "$SSH_PORT" ]]; then
    ssh -p "$SSH_PORT" "$@"
  else
    ssh "$@"
  fi
}
# 同步给远程 .env 用的 token（不设则交互式问或随机生成）
PB_SYNC_TOKEN="${PB_SYNC_TOKEN:-}"
PB_MYSQL_PASSWORD="${PB_MYSQL_PASSWORD:-}"
PB_SERVER_PORT="${PB_SERVER_PORT:-8090}"
# MySQL 部署模式：1=内置 mysql（默认）；0=外置 mysql（需提供 PB_MYSQL_DSN）
PB_USE_BUILTIN_MYSQL="${PB_USE_BUILTIN_MYSQL:-1}"
# 外置 mysql 模式下，用户提供的完整 DSN（指向已安装的 mysql 实例）
PB_MYSQL_DSN="${PB_MYSQL_DSN:-}"

# ---------- 本地自检 ----------
command -v rsync >/dev/null || die "本地缺少 rsync，请先安装：brew install rsync / apt install rsync"
command -v ssh >/dev/null   || die "本地缺少 ssh"

# 取本脚本所在目录（server/）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/Dockerfile" ]] || die "未找到 $SCRIPT_DIR/Dockerfile，请在 server/ 目录下运行本脚本"

if [[ -n "$SSH_PORT" ]]; then
  log "目标主机：${SSH_HOST}（端口 $SSH_PORT）"
else
  log "目标主机：${SSH_HOST}（端口/密钥走 ~/.ssh/config）"
fi
log "远程目录：$REMOTE_DIR"
if [[ "$INIT_MODE" = "1" ]]; then
  warn "首次部署模式：远程若 .env 不存在会随机生成"
  if [[ "$PB_USE_BUILTIN_MYSQL" = "1" ]]; then
    log "MySQL 模式：内置（compose 拉起 mysql 容器）"
  else
    log "MySQL 模式：外置（用户已安装 mysql）"
    [[ -z "$PB_MYSQL_DSN" ]] && die "外置 mysql 模式需要 PB_MYSQL_DSN 环境变量，例如：
  PB_USE_BUILTIN_MYSQL=0 \\
  PB_MYSQL_DSN='root:xxx@tcp(192.168.1.20:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local' \\
  $0 $SSH_HOST --init

注意：外置 mysql 需用户自行执行 sql/init.sql 建库建表。"
  fi
fi

# ---------- 远程自检：docker / compose / rsync ----------
log "检查远程 docker / rsync 环境..."
pb_ssh "$SSH_HOST" "
  command -v rsync >/dev/null 2>&1 || { echo 'ERR: rsync not installed'; exit 1; }
  command -v docker >/dev/null 2>&1 || { echo 'ERR: docker not installed'; exit 1; }
  docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1 || { echo 'ERR: docker compose not installed'; exit 1; }
  echo OK
" | tail -1 | grep -q OK || die "远程缺少依赖，请按需安装：

  # rsync（必装，rsync 同步源码用）
  #   Ubuntu/Debian:  sudo apt update && sudo apt install -y rsync
  #   CentOS/RHEL:    sudo yum install -y rsync
  #   Alpine:         sudo apk add --no-cache rsync

  # docker / docker compose（容器运行用）
  #   curl -fsSL https://get.docker.com | sh
  #   sudo usermod -aG docker \$USER  # 然后重新登录一次
  #   macOS 上可用 OrbStack / Docker Desktop"
ok "远程 docker / rsync 可用"

# ---------- 创建远程目录 ----------
log "确保远程目录存在：$REMOTE_DIR"
pb_ssh "$SSH_HOST" "mkdir -p $REMOTE_DIR"
ok "远程目录就绪"

# ---------- rsync 同步源码 ----------
log "rsync 同步 server/ → $SSH_HOST:$REMOTE_DIR/"
# 排除：
#   - .env / .env.*     本地环境变量不污染远程
#   - 本地构建产物     /bin /dist *.exe
#                     internal/web/files/{node_modules,dist,.vite}
#                     （Docker 构建时在 frontend 阶段重新 pnpm install + build）
#   - .git / IDE        无关代码
#   - deploy.sh 自身    避免循环
#   - README.md         远程不需要文档（可选保留，但减小体积）
rsync -azP --delete \
  -e "$RSYNC_SSH" \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='! .env.example' \
  --exclude='/bin/' \
  --exclude='/dist/' \
  --exclude='*.exe' \
  --exclude='*.test' \
  --exclude='*.out' \
  --exclude='.git/' \
  --exclude='.idea/' \
  --exclude='.vscode/' \
  --exclude='*.log' \
  --exclude='vendor/' \
  --exclude='deploy.sh' \
  --exclude='internal/web/files/node_modules/' \
  --exclude='internal/web/files/dist/' \
  --exclude='internal/web/files/.vite/' \
  "$SCRIPT_DIR/" "$SSH_HOST:$REMOTE_DIR/"
ok "代码同步完成"

# ---------- 首次部署：生成 .env ----------
if [[ "$INIT_MODE" = "1" ]]; then
  log "首次部署：检查远程 .env 是否已存在"
  ENV_EXISTS=$(pb_ssh "$SSH_HOST" "test -f $REMOTE_DIR/.env && echo yes || echo no")
  if [[ "$ENV_EXISTS" = "yes" ]]; then
    warn "远程 .env 已存在，跳过生成（如需重置请先 ssh 删除该文件）"
  else
    # 自动生成强随机 token（两种模式都需要）
    [[ -z "$PB_SYNC_TOKEN" ]] && PB_SYNC_TOKEN=$(openssl rand -hex 16 2>/dev/null || pb_ssh "$SSH_HOST" "head -c 16 /dev/urandom | xxd -p")

    if [[ "$PB_USE_BUILTIN_MYSQL" = "1" ]]; then
      # ---------- 内置 mysql 模式 ----------
      [[ -z "$PB_MYSQL_PASSWORD" ]] && PB_MYSQL_PASSWORD=$(openssl rand -hex 16 2>/dev/null || pb_ssh "$SSH_HOST" "head -c 16 /dev/urandom | xxd -p")
      MYSQL_DSN_VALUE="root:${PB_MYSQL_PASSWORD}@tcp(mysql:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local"

      log "生成远程 .env（内置 mysql 模式）"
      pb_ssh "$SSH_HOST" "cat > $REMOTE_DIR/.env <<EOF
# 由 deploy.sh --init 自动生成（内置 mysql 模式）
SYNC_TOKEN=$PB_SYNC_TOKEN
MYSQL_DSN=$MYSQL_DSN_VALUE
MYSQL_ROOT_PASSWORD=$PB_MYSQL_PASSWORD
MYSQL_DATABASE=personal_butler
SERVER_PORT=$PB_SERVER_PORT
# 启用内置 mysql profile（compose 同时拉起 server + mysql）
COMPOSE_PROFILES=mysql
EOF"
      ok "远程 .env 已生成"
      printf "${GREEN}══════════════════════════════════════════════════${NC}\n"
      printf "${GREEN}请妥善保存以下凭据（仅展示一次）：${NC}\n"
      printf "  SYNC_TOKEN         = %s\n" "$PB_SYNC_TOKEN"
      printf "  MYSQL_ROOT_PASSWORD= %s\n" "$PB_MYSQL_PASSWORD"
      printf "  MYSQL_DSN          = %s\n" "$MYSQL_DSN_VALUE"
      printf "  SERVER_PORT        = %s\n" "$PB_SERVER_PORT"
      printf "  COMPOSE_PROFILES   = mysql（启用内置 mysql）\n"
      printf "${GREEN}══════════════════════════════════════════════════${NC}\n"
    else
      # ---------- 外置 mysql 模式 ----------
      # PB_MYSQL_DSN 在前面已校验非空
      log "生成远程 .env（外置 mysql 模式）"
      pb_ssh "$SSH_HOST" "cat > $REMOTE_DIR/.env <<EOF
# 由 deploy.sh --init 自动生成（外置 mysql 模式）
# 用户已自行安装 mysql，compose 只拉起 server
SYNC_TOKEN=$PB_SYNC_TOKEN
MYSQL_DSN=$PB_MYSQL_DSN
SERVER_PORT=$PB_SERVER_PORT
# 不写 COMPOSE_PROFILES=mysql，避免 compose 拉起内置 mysql
EOF"
      ok "远程 .env 已生成"
      printf "${GREEN}══════════════════════════════════════════════════${NC}\n"
      printf "${GREEN}请妥善保存以下凭据（仅展示一次）：${NC}\n"
      printf "  SYNC_TOKEN         = %s\n" "$PB_SYNC_TOKEN"
      printf "  MYSQL_DSN          = %s\n" "$PB_MYSQL_DSN"
      printf "  SERVER_PORT        = %s\n" "$PB_SERVER_PORT"
      printf "  COMPOSE_PROFILES   = （未启用，使用外部 mysql）\n"
      printf "${YELLOW}⚠ 外置模式需自行在 mysql 上执行 sql/init.sql 建库建表${NC}\n"
      printf "${GREEN}══════════════════════════════════════════════════${NC}\n"
    fi
  fi
else
  log "非首次部署模式：要求远程 .env 已存在"
  ENV_EXISTS=$(pb_ssh "$SSH_HOST" "test -f $REMOTE_DIR/.env && echo yes || echo no")
  [[ "$ENV_EXISTS" = "yes" ]] || die "远程 $REMOTE_DIR/.env 不存在，请用 --init 首次部署：
  $0 $SSH_HOST --init"
  ok "远程 .env 存在"
fi

# ---------- 远程构建 + 启动 ----------
log "远程执行 docker compose up -d --build..."
# 这里强制用 v2 语法 `docker compose`（不是 v1 的 `docker-compose`）
# 用 --build 是为了用最新代码 rebuild server 镜像
# 加上 --remove-orphans 防止历史残留容器
# 不指定服务名：compose 会按 .env 中的 COMPOSE_PROFILES 决定是否拉起 mysql
#   - 内置模式（COMPOSE_PROFILES=mysql）：up 时自动 pull mysql 镜像 + build server
#   - 外置模式（无 COMPOSE_PROFILES）：只 build + 启动 server
# 不单独执行 `docker compose pull`：
#   - server 是本地 build 出来的，去 docker.io pull 会 i/o timeout（镜像名不存在于 registry）
#   - mysql 镜像由 up 时自动拉取，无需显式 pull
pb_ssh "$SSH_HOST" "
  set -e
  cd $REMOTE_DIR
  docker compose up -d --build --remove-orphans 2>&1 | tail -30
"
ok "容器已启动"

# ---------- 等待健康检查 ----------
log "等待 /healthz 返回 200..."
HEALTHY=0
for i in $(seq 1 30); do
  if pb_ssh "$SSH_HOST" "curl -fsS http://127.0.0.1:$PB_SERVER_PORT/healthz" >/dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 2
  printf "."
done
echo

if [[ "$HEALTHY" = "1" ]]; then
  ok "服务端健康检查通过"
else
  warn "/healthz 30s 内未就绪，可能还在启动；查看日志："
  echo "  $SSH_CMD_PREFIX $SSH_HOST 'cd $REMOTE_DIR && docker compose logs --tail 50 server'"
  exit 1
fi

# ---------- 输出访问地址 ----------
REMOTE_IP=$(pb_ssh "$SSH_HOST" "
  # 优先取公网 IP（若有）；失败则取首个内网 IPv4
  curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || \
  ip -4 -o addr show scope global 2>/dev/null | awk '{print \$4}' | head -1 | cut -d/ -f1
" 2>/dev/null || echo "<host>")

printf "\n${GREEN}══════════════════════════════════════════════════${NC}\n"
printf "${GREEN}部署成功${NC}\n"
printf "  iOS 同步地址：  http://%s:%s\n" "$REMOTE_IP" "$PB_SERVER_PORT"
printf "  Web 表单录入：  http://%s:%s/web\n" "$REMOTE_IP" "$PB_SERVER_PORT"
printf "  健康检查：      http://%s:%s/healthz\n" "$REMOTE_IP" "$PB_SERVER_PORT"
printf "\n常用维护命令（在远程 %s 目录下执行）：\n" "$REMOTE_DIR"
printf "  docker compose logs -f server       # 查日志\n"
printf "  docker compose restart server       # 重启 server\n"
printf "  docker compose down                # 停止并清理容器\n"
printf "  docker compose down -v             # ⚠️ 连数据卷一起清掉\n"
printf "${GREEN}══════════════════════════════════════════════════${NC}\n"
