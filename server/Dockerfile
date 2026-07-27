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
