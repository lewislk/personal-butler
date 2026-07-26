# PersonalButler · 备份 & 局域网同步 · 模块级 SPEC

> 模块职责：把本机所有业务数据（SwiftData + Keychain）组装成统一的 `SyncPayload` JSON，用于两条独立通道：**本地文件备份**（ShareLink 导出）与**局域网 HTTP 全量同步**（POST/GET 到用户自建的内网服务）。所有操作**必须用户手动触发**，每次都过生物识别。

## 1. 范围与边界

本模块负责：

- `SyncPayload` 结构定义与组装（含全部 10 类实体 + Keychain 明文）
- 本地 JSON 备份：编码 → 临时目录 → `ShareLink`
- 局域网 HTTP 4 接口：`/sync/upload` / `/sync/download` / `/sync/info` / `/sync/clear`（当前 MVP 仅实现前两个）
- 服务器配置持久化（IP / Token / DeviceID）
- 生物识别门禁（每次操作前）
- 最近同步时间的展示与更新（`AppEnvironment.lastSyncTime`）

不覆盖：

- 服务端实现（用户自建）
- 差量同步、冲突合并（当前只支持全量覆盖式，MVP `restore` 仅占位不落库）
- 自动 / 后台同步（业务规则明确要求手动）
- 备份文件 AES 加密（PRD 二期）

## 2. 核心概念

### SyncPayload

同步数据包顶层结构（`Data/Mapper/SyncPayload.swift`）：

```swift
struct SyncPayload: Codable {
    var syncMeta: SyncMeta          // 元数据
    var data: SyncData              // 业务实体列表
}
```

`SyncMeta`：`deviceId / syncTimestamp / appVersion / dataVersion (=3)`

`SyncData` 内含 9 个列表 + 1 个 setting map：
- `todoList / scheduleList / anniversaryList / passwordList / otpList / foodRecordList / cookRecipeList / noteList / appModuleList / setting`

每类实体对应一个 `SyncXxxDTO`，与 `@Model` 结构对齐；日期统一 `Double`（unix timestamp），UUID 统一 `String`。

**敏感数据**：`passwordList[].passwordPlain` 与 `otpList[].secretPlain` 携带 Keychain 明文，仅在内存组装与局域网传输阶段存在，落磁盘只发生在用户主动导出的本地 JSON 备份中。

### 请求头

| Header | 值 |
|--------|----|
| `Content-Type` | `application/json` |
| `X-Device-ID` | `AppSyncConfig.deviceID`（本机首次生成的稳定 UUID） |
| `X-Sync-Token` | `AppSyncConfig.token`（用户配置的静态密钥） |

### 端点

| Method | Path | 用途 | 已实现 |
|--------|------|------|--------|
| POST | `/sync/upload` | 上传本机全量数据 | ✅ |
| GET | `/sync/download` | 拉取本设备备份 | ✅ |
| GET | `/sync/info` | 查询备份摘要 | ❌（MVP 未实现） |
| DELETE | `/sync/clear` | 清空本设备备份 | ❌（MVP 未实现） |

### AppEnvironment.markSynced()

同步成功后调用；更新 `lastSyncTime` 并落 UserDefaults；MineView 与 LanSyncView 读同一个来源。

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| Payload 定义 | `Data/Mapper/SyncPayload.swift` | Codable DTO |
| 用例 | `Domain/UseCases/BackupSyncUseCase.swift` | `buildPayload / upload / download / restore` |
| 局域网同步 UI | `Presentation/Views/SubPages/LanSyncView.swift` | 从 MineView `.sheet` 弹出 |
| 本地备份 UI | `Presentation/Sheets/LocalBackupSheet.swift` | 从 MineView `.sheet` 弹出；导出 + 从文件恢复共用同一张 sheet |
| 服务器配置 | `App/AppSyncConfig.swift` | UserDefaults 读写 |
| 生物识别 | `Core/Auth/LocalAuthService.swift` | 所有操作前必调 |
| 敏感数据 | `Core/Utils/KeychainManager.swift` | 组装 payload 时读明文 |

## 4. 核心场景

### 组装 SyncPayload

**代码入口：** `BackupSyncUseCase.swift` · `buildPayload() throws -> SyncPayload`

**业务规则：**

- `syncMeta`：`deviceId = AppSyncConfig.deviceID`；`syncTimestamp = Int64(unix)`；`appVersion = "1.0.0"`（硬编码）；`dataVersion = 2`（硬编码）
- 扫描全部 `@Model` 表：`Todo / Schedule / Anniversary / Password / OTP / Food / CookRecipe / Note / AppModule`
- `PasswordAccount / OTPAccount` 需要额外从 Keychain 读明文；读失败以 `""` 兜底不阻断
- `AppSetting` 当前作为 `setting: [:]` 空 map 占位（MVP 未纳入同步）

**实现逻辑：**

1. `MainActor` 上下文（`@MainActor final class BackupSyncUseCase`），持有传入的 `ModelContext`
2. 每类实体：`(try? context.fetch(FetchDescriptor<T>())) ?? []`
3. 逐个 `.map { SyncXxxDTO(...) }` 转换：
   - UUID → `id.uuidString`
   - Date → `timeIntervalSince1970: Double`
   - 枚举 → `xxxRaw: String`
   - 密码明文：`KeychainManager.load($0.passwordKeychainKey) ?? ""`
   - OTP 密钥：`KeychainManager.load($0.secretKeychainKey) ?? ""`
4. 组合 `SyncData(...)`，再 `SyncPayload(syncMeta:, data:)`

### 本地 JSON 备份导出 / 导入

**代码入口：** `LocalBackupSheet.swift` · `doExport()` / `doImport(url:)`（同一张 sheet 承担导出 + 从文件恢复；MineView 的"数据备份 / 恢复"单一入口打开这里）

**业务规则：**

- 导出与导入前都必调 `LocalAuthService.authenticate(...)`
- 备份文件名：`PersonalButler_yyyyMMdd_HHmmss.json`，落到 `FileManager.default.temporaryDirectory`
- **文件落地在 App 沙盒 `tmp/`，用户看不到、系统会回收** —— 导出成功后必须由用户点 `ShareLink` → "存储到文件" 才算真正保存。UI 上用一个高亮 Section（橙色 `exclamationmark.triangle.fill` + 大号 ShareLink 按钮 + 文件名 + 明确提示）承担引导；文案强调"生成 ≠ 已保存"
- 导入通过 `.fileImporter(allowedContentTypes: [.json])` 选取文件，选定后弹 `.alert` 二次确认（destructive 按钮"确认覆盖"），确认后走 `BackupSyncUseCase.restore` 全量覆盖
- 明确警告：文件内包含密码/2FA 密钥明文；恢复不可撤销

**为什么不改成 Documents 目录：** 落 Documents + Info.plist `UIFileSharingEnabled` 能让文件在"文件 App / 我的 iPhone / PersonalButler" 下直接可见，但会把整个 App 沙盒对文件 App 开放（用户能看到 SwiftData 的 SQLite、缓存等所有内部文件），对隐私管家类应用不合适。tmp + ShareLink 路径下用户主动选目标位置，反而是更干净的边界；代价是"必须点分享"，用 UI 强引导消化。

**实现逻辑：**

导出（`doExport`）：
1. `guard !running` 防抖 + 生物识别
2. `let payload = try uc.buildPayload()`
3. `JSONEncoder().outputFormatting = [.prettyPrinted]` → `enc.encode(payload)` → `data.write(to: url)`
4. `exportURL = url`；渲染专门的"待保存"Section（橙色警示 + `ShareLink(item: url)`）
5. 异常 → `message = "生成备份文件失败：..."` 并把 `exportURL` 置 nil，避免残留旧文件 URL 让用户误以为还可分享

导入（`doImport(url:)`）：
1. `guard !running` 防抖 + 生物识别
2. `url.startAccessingSecurityScopedResource()`（fileImporter 给的是 security-scoped URL），`defer` 里 stop
3. `let data = try Data(contentsOf: url)` → `try JSONDecoder().decode(SyncPayload.self, from: data)`
4. `try uc.restore(payload)` — 走与局域网下载相同的 clear + rebuild + Keychain 三段处理
5. `DecodingError` 单独 catch → "备份文件格式无效：..."

### 局域网上传

**代码入口：** `LanSyncView.swift` · `doUpload()` → `BackupSyncUseCase.upload()`

**业务规则：**

- 服务器地址空 → 抛 `SyncError.serverEmpty`，UI "上传"按钮 `.disabled(host.isEmpty)` 已提前阻断
- 触发前必调 `LocalAuthService.authenticate(...)`
- 请求超时 10 秒
- POST body 为完整 `SyncPayload` JSON
- 成功后 `env.markSynced()` 记录时间；UI 展示 "上传成功"
- **并发保护**：服务端按 `X-Device-ID` 做进程内 `TryLock` 单飞（`sync.Map[deviceID]*sync.Mutex`），上一次 upload/clear 未结束前重复调用会立即回 `code=2003 sync in progress`；客户端 UI 层也应在 `doUpload()` 期间 disabled 按钮做本地防抖

**实现逻辑：**

1. `LanSyncView.doUpload`:
   - `guard !running else { return }`（Face ID 期间也算忙，防重复触发）
   - `running = true; defer { running = false }`
   - `guard await LocalAuthService.authenticate(...) else { return }`
   - `try await uc.upload()` → `env.markSynced()` + `message = "上传成功"`
   - `catch SyncError.inProgress` → `message = "上一次同步还在进行，请稍后重试"`
   - `catch` → `message = "上传失败：\(error.localizedDescription)"`
2. `BackupSyncUseCase.upload`:
   - `let payload = try buildPayload()`
   - `var req = try makeRequest(path: "/sync/upload", method: "POST")`
   - `req.httpBody = try JSONEncoder().encode(payload)`
   - `let (data, _) = try await URLSession.shared.data(for: req)`
   - `_ = try decodeResponse(data, as: Empty.self)` — 解析 `{code, msg, data?}`，`code=0` 成功、`code=2003` 抛 `SyncError.inProgress`、其它非零抛 `SyncError.server(code, msg)`
3. `makeRequest`:
   - `guard !AppSyncConfig.host.isEmpty else throw serverEmpty`
   - `URL = "http://\(host):\(defaultPort)\(path)"`
   - 设置 3 个 header + `timeoutInterval = 10`

### 局域网下载 / 恢复

**代码入口：** `LanSyncView.swift` · `doDownload()` → `BackupSyncUseCase.download()` + `restore()`

**业务规则：**

- 生物识别通过后 GET `/sync/download`
- 解析 `APIResp<SyncPayload>`（`{code, msg, data}` 包装），根据 code 走 `SyncError` 分支
- 拿到 `payload.data` 后调 `restore(payload)`
- **`restore` 全量覆盖语义**：先 `clearAllSyncedEntities()` 清空所有可同步 @Model，再按 payload 各 list 反序列化 `context.insert`，最后一次 `context.save()`；中途抛错 `context.rollback()`。整个过程关闭 `context.autosaveEnabled`，防止 SwiftUI 让出主线程时 autosave 提前落盘。
- **Keychain 处理**：先收集旧 `pwd.*` / `otp.*` key，`save()` 成功后再删；新记录用 `pwd.<uuid>` / `otp.<uuid>`（UUID 复用 `@Model.id`）；rebuild 抛错时反向清理已写入的新 key，旧 Keychain 不动，保证失败时旧密码仍可用。
- **不参与 restore**：`AppSetting`（未纳入 `SyncPayload.setting`，AGENTS.md §7）
- 成功后 `markSynced()`；失败 UI 展示错误信息

**实现逻辑：**

1. `BackupSyncUseCase.download`:
   - `let req = try makeRequest(path: "/sync/download", method: "GET")`
   - `let (data, _) = try await URLSession.shared.data(for: req)`
   - `let wrap = try decodeResponse(data, as: SyncPayload.self)` — 复用 upload 同一套 code 分派逻辑
   - `guard let payload = wrap.data else { throw SyncError.decode }`
2. `restore(_ payload:)`：
   - 收集旧 Keychain key（`existingPwds.map { $0.passwordKeychainKey } + existingOTPs.map { $0.secretKeychainKey }`）
   - `context.autosaveEnabled = false`（`defer` 里恢复）
   - `clearAllSyncedEntities()` — 逐条 `context.delete(obj)`（**不**用 `context.delete(model:)` 批量，那绕过 context pending queue，rollback 撤不回）
   - `rebuild(from:newKeychainKeys:)` — 各 DTO → `context.insert(@Model)`；Password/OTP 先 `KeychainManager.save` 再 insert，key 累积到 `newKeychainKeys`
   - `try context.save()` 成功 → 遍历 oldKeychainKeys 清理；失败 → `context.rollback()` + 遍历 newKeychainKeys 清理，throw
3. UI 层：`env.markSynced()`；message = "恢复成功"

### 错误处理

**代码入口：** `BackupSyncUseCase.SyncError`

| Case | 触发场景 | 用户可见提示 |
|------|---------|-------------|
| `.serverEmpty` | `AppSyncConfig.host.isEmpty` | 请先配置同步服务器地址 |
| `.network(let m)` | 预留网络错误封装（当前未主动抛，`URLSession` 原生错误也会经 `error.localizedDescription` 呈现） | 网络错误：… |
| `.decode` | download 返回体解码失败 / `data == nil` | 服务端返回数据无法解析 |
| `.inProgress` | 服务端 `code=2003`：同一 device 已有 upload/clear 事务在跑（`SyncService.deviceLocks` TryLock 失败） | 上一次同步还在进行，请稍后重试 |
| `.noBackup` | 服务端 `code=2002`：该 device 尚未上传过任何数据 | 服务器上还没有该设备的备份，请先上传一次 |
| `.server(code, msg)` | 其它非零 code 的兜底（1001/1002/1003/2001/5000） | 服务端错误（\(code)）：\(msg) |

上层统一 catch → `message = "上传失败/恢复失败/导出失败：\(error.localizedDescription)"`

### 服务器配置管理

**代码入口：** `LanSyncView.swift` · Section「局域网服务器」

**业务规则：**

- IP 与 Token 输入后 `.onChange` 立即写回 `AppSyncConfig`（不需要点保存）
- 端口固定 8090，展示只读
- 展示当前 DeviceID 的前 8 字符（`+ "…"`）

**实现逻辑：**

1. `@State host = AppSyncConfig.host`；`.onChange(of: host) { _, v in AppSyncConfig.host = v }`
2. Token 同上
3. DeviceID：`AppSyncConfig.deviceID.prefix(8) + "…"`
4. lastSyncTime：`env.lastSyncTime.map { fmt($0) } ?? "未同步"`

## 5. 参考资料

- 代码：
  - `personal-butler/Domain/UseCases/BackupSyncUseCase.swift`
  - `personal-butler/Data/Mapper/SyncPayload.swift`
  - `personal-butler/Presentation/Views/SubPages/LanSyncView.swift`
  - `personal-butler/Presentation/Sheets/LocalBackupSheet.swift`
  - `personal-butler/App/AppSyncConfig.swift`
  - `personal-butler/App/AppEnvironment.swift`
- 文档：
  - `docs/PRD.md § 12 数据备份 & 局域网同步`
  - `CLAUDE_BACK.md § 四 局域网同步 REST 接口 / § 五-2/3 上传下载流程 / § 六 安全设计`
- 相关模块：
  - [module-password-otp-spec.md](./module-password-otp-spec.md)（Keychain 密钥来源）
  - [module-infra-spec.md](./module-infra-spec.md)（`KeychainManager` / `LocalAuthService`）

## 6. 变更历史

- v2 (2026-07-26): SyncFoodDTO 增加 placeName / address / latitude / longitude 四个可选字段（美食记录位置录入）
  - `placeName?: String`   POI 名称，dataVersion ≥ 2 起
  - `address?: String`     结构化地址，dataVersion ≥ 2 起
  - `latitude?: Double`    WGS84 纬度，dataVersion ≥ 2 起
  - `longitude?: Double`   WGS84 经度，dataVersion ≥ 2 起
- v3 (2026-07-26): SyncFoodDTO 追加变更
  - rating: Int → Double（半星评分，Codable 天然兼容老 JSON 整数）
  - iconImageBase64?: String（图片图标，base64 编码的 JPEG bytes）
  - URLRequest.timeoutInterval 由 10s 放宽为 25s（图片显著增大 payload）
