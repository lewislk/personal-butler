# PersonalButler · 个人生活管家

> 一个纯本地、零账号、零广告的 iOS 个人生活管家 App。所有数据只保存在你自己的设备上，只有你主动触发时，才会通过局域网与你自建的服务器同步一次。

面向 AI / 开发者视角的仓库入口见 [AGENTS.md](./AGENTS.md)，详细模块规格见 [docs/module-spec/](./docs/module-spec/index.md)。

---

## ✨ 这个项目是什么

PersonalButler 把日常琐事聚合到一个 App 里，让你不用在十几个应用之间来回切换：

- 📝 **待办清单**：普通任务 + 来自日程 / 纪念日的自动待办
- 📅 **日程表**：日历视图，标签分色，看清接下来一周
- 🎂 **纪念日**：生日 / 恋爱 / 结婚等倒数日，支持农历
- 🗒️ **随手笔记**：轻量 Markdown 笔记
- 🔐 **密码本 + 2FA 验证器**：明文密码进 Keychain，TOTP 6 位动态码本地生成
- 🍜 **美食打卡**：记录去过的餐厅 / 吃过的菜
- 📖 **菜谱收藏**：把喜欢的做法收进来
- 🧳 **更多**：记账 / 健康 / 旅行 / 观影（PRD 二期）

**核心承诺**：

| 你担心的 | 我们的答案 |
|---------|-----------|
| 数据被上传到某厂云端？ | ❌ 不会。App 无账号体系、无外网请求 |
| 换手机数据丢了？ | ✅ 支持导出 JSON 本地备份 + 局域网同步到自建服务器 |
| 密码明文会泄露？ | ✅ 明文只进 iOS Keychain，SwiftData 库里不存 |
| 打开 App 别人偷看？ | ✅ 敏感操作走 Face ID / Touch ID |
| 有隐藏埋点吗？ | ❌ 零第三方 SDK，零分析统计 |

---

## 🎯 核心功能一览

### 主页 · Home
- 今日待办 / 本周待办卡片，自动合并日程 & 纪念日
- 快捷 6 宫格进入常用模块

### 全部应用 · All App
- 已上线模块 + "即将上线" 模块（灰色占位卡片）

### 我的 · Mine
- 数据备份（导出 JSON / 局域网同步配置）
- 主题色 / 关于 / 清除缓存

### 密码 · Password（生物识别门禁）
- 密码明文永不进数据库，只落 Keychain
- 内置 TOTP 2FA 验证器：30 秒滚动 6 位动态码
- 支持按分组 / 收藏筛选

### 日程 · Schedule
- 月视图 + 日程列表
- 颜色标签，一键跳转当天

### 纪念日 · Anniversary
- 公历 / 农历自动转换
- 首屏突出最近一个倒数日

### 笔记 · Notes
- 快速新建 / 编辑 / 收藏

### 局域网同步（可选）
- 用户在局域网内自建 HTTP 服务（`http://<host>:8090`）
- 客户端只在你**手动点上传 / 下载**时才通信
- 4 个端点全量 JSON 传输，附 `X-Device-ID` / `X-Sync-Token`
- 详细协议见 [docs/module-spec/module-backup-sync-spec.md](./docs/module-spec/module-backup-sync-spec.md)

---

## 🛠 技术栈

| 领域 | 选择 |
|------|------|
| 语言 | Swift 5.10+ |
| 平台 | iOS 18+（仅 iPhone） |
| UI | 纯 SwiftUI（无 UIKit） |
| 架构 | Clean Architecture 分层，MVP 阶段视图直连 `ModelContext`；跨模块聚合抽为 UseCase |
| 本地存储 | SwiftData（`@Model` / SQLite） |
| 敏感存储 | Keychain（明文密码 / TOTP 密钥） |
| 轻配置 | UserDefaults |
| 加密 | CryptoKit（HMAC-SHA1 / TOTP RFC 6238） |
| 生物识别 | LocalAuthentication（`.deviceOwnerAuthentication`） |
| 网络 | 仅 `URLSession` 访问局域网 HTTP，无任何外网调用 |
| 第三方依赖 | **零**（不用 SPM / CocoaPods） |
| 语言/语系 | 简体中文 UI（`zh-Hans`） |

---

## 📁 目录结构

```
personal-butler/
├── App/                      # App 入口 / 全局环境 / 根路由 / 主题
├── Assets.xcassets/          # 图标 / 主色板资源
├── Core/                     # 无业务耦合的通用底座
│   ├── Auth/                 #   ├─ 生物识别封装（唯一入口）
│   ├── Constants/            #   ├─ UI 尺寸 / 圆角 / 间距常量
│   ├── Extensions/           #   ├─ Date / Color / View 扩展
│   ├── Network/              #   ├─ URLSession 封装（局域网 HTTP）
│   └── Utils/                #   └─ Keychain / TOTP / 农历 / 通知
├── Domain/                   # 领域层
│   ├── Models/               #   ├─ 10 个 SwiftData @Model（Todo/日程/密码/2FA/...）
│   └── UseCases/             #   └─ 跨模块聚合（目前仅 BackupSyncUseCase）
├── Data/                     # 数据层
│   ├── LocalDataSource/      #   ├─ 首启种子数据（幂等）
│   ├── Mapper/               #   ├─ 同步 JSON DTO 定义
│   └── Repository/           #   └─ 数据访问适配（预留）
├── Presentation/             # 表现层
│   ├── Components/           #   ├─ 通用 UI 组件（FAB / Segmented / TagBar…）
│   ├── Sheets/               #   ├─ 本地备份等浮层
│   ├── ViewModels/           #   ├─ 页面 ViewModel（预留）
│   └── Views/                #   └─ 页面
│       ├── MainTab/          #      ├─ Home / AllApp / Mine 主 Tab
│       ├── SubPages/         #      ├─ 各业务模块子页面
│       ├── AppModuleRouter   #      ├─ 模块 id → 子页面工厂
│       └── RootView          #      └─ 常驻 NavigationStack
├── Preview Content/          # SwiftUI Preview 资源
└── docs/                     # 项目文档
    ├── PRD.md                #   ├─ 产品需求
    ├── TDD.md                #   ├─ 技术设计（历史存档）
    ├── UI_DEMO.md            #   ├─ 视觉规范
    ├── module-spec/          #   └─ 各模块 SPEC + 项目 SPEC
    └── ui-prototype/         #      UI 原型 HTML
```

---

## 🚀 快速开始

```bash
# 打开工程
open personal-butler.xcodeproj
```

在 Xcode 里 `Cmd + R` 运行到 iOS 18+ 模拟器或真机即可。首次启动会自动写入模块入口种子数据，无需任何配置。

**（可选）启用局域网同步**：

1. 在你的电脑 / NAS / 树莓派上跑一个符合 [同步协议](./docs/module-spec/module-backup-sync-spec.md) 的服务
2. App 内 "我的 → 数据备份 → 局域网同步"，填入 `host` + `token`
3. 手动点 "上传" / "下载" 触发全量同步

---

## 📜 许可

个人项目，暂未开源许可证。如需引用，请先联系作者(liukunauh@gmail.com)。

