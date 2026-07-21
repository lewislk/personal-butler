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

`SyncMeta`：`deviceId / syncTimestamp / appVersion / dataVersion (=1)`

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
| GET | `/sync/download` | 拉取本设备备份 | ✅（`restore` 未真正覆盖，占位） |
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
| 本地备份 UI | `Presentation/Sheets/LocalBackupSheet.swift` | 从 MineView `.sheet` 弹出 |
| 服务器配置 | `App/AppSyncConfig.swift` | UserDefaults 读写 |
| 生物识别 | `Core/Auth/LocalAuthService.swift` | 所有操作前必调 |
| 敏感数据 | `Core/Utils/KeychainManager.swift` | 组装 payload 时读明文 |

## 4. 核心场景

### 组装 SyncPayload

**代码入口：** `BackupSyncUseCase.swift` · `buildPayload() throws -> SyncPayload`

**业务规则：**

- `syncMeta`：`deviceId = AppSyncConfig.deviceID`；`syncTimestamp = Int64(unix)`；`appVersion = "1.0.0"`（硬编码）；`dataVersion = 1`
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

### 本地 JSON 备份导出

**代码入口：** `LocalBackupSheet.swift` · `doExport()` async

**业务规则：**

- 触发前必调 `LocalAuthService.authenticate(reason: "导出备份")`
- 备份文件文件名：`PersonalButler_yyyyMMdd_HHmmss.json`
- 落到 `FileManager.default.temporaryDirectory`
- 展示 `ShareLink(item: url)`，供用户分享到「文件 App / iCloud Drive / AirDrop」
- 明确警告：文件内包含密码/2FA 密钥明文

**实现逻辑：**

1. 生物识别 → 通过后进入 do-block
2. `let payload = try uc.buildPayload()`
3. `JSONEncoder().outputFormatting = [.prettyPrinted]`
4. `enc.encode(payload)` → `data.write(to: url)`
5. `exportURL = url`；Section 中出现 ShareLink 按钮
6. 异常 → `message = "导出失败：\(error.localizedDescription)"`

### 局域网上传

**代码入口：** `LanSyncView.swift` · `doUpload()` → `BackupSyncUseCase.upload()`

**业务规则：**

- 服务器地址空 → 抛 `SyncError.serverEmpty`，UI "上传"按钮 `.disabled(host.isEmpty)` 已提前阻断
- 触发前必调 `LocalAuthService.authenticate(...)`
- 请求超时 10 秒
- POST body 为完整 `SyncPayload` JSON
- 成功后 `env.markSynced()` 记录时间；UI 展示 "上传成功"

**实现逻辑：**

1. `LanSyncView.doUpload`:
   - `guard await LocalAuthService.authenticate(...) else { return }`
   - `running = true; defer { running = false }`
   - `try await uc.upload()` → `env.markSynced()` + `message = "上传成功"`
   - `catch` → `message = "上传失败：\(error.localizedDescription)"`
2. `BackupSyncUseCase.upload`:
   - `let payload = try buildPayload()`
   - `var req = try makeRequest(path: "/sync/upload", method: "POST")`
   - `req.httpBody = try JSONEncoder().encode(payload)`
   - `_ = try await URLSession.shared.data(for: req)`（当前未解析 `SyncResponse.code`，只要 URL 请求不抛错即视为成功）
3. `makeRequest`:
   - `guard !AppSyncConfig.host.isEmpty else throw serverEmpty`
   - `URL = "http://\(host):\(defaultPort)\(path)"`
   - 设置 3 个 header + `timeoutInterval = 10`

### 局域网下载 / 恢复

**代码入口：** `LanSyncView.swift` · `doDownload()` → `BackupSyncUseCase.download()` + `restore()`

**业务规则：**

- 生物识别通过后 GET `/sync/download`
- 解析 `SyncResponse<SyncPayload>`（`{code, msg, data}` 包装）
- 拿到 `payload.data` 后调 `restore(payload)`
- **MVP：`restore` 仅 `context.save()` 占位，不真正覆盖本地数据**（避免误删）；生产版本应先清空表再批量插入 + Keychain 覆盖
- 成功后 `markSynced()`；失败 UI 展示错误信息

**实现逻辑：**

1. `BackupSyncUseCase.download`:
   - `let req = try makeRequest(path: "/sync/download", method: "GET")`
   - `let (data, _) = try await URLSession.shared.data(for: req)`
   - `struct Wrap: Codable { code: Int; msg: String; data: SyncPayload? }`
   - `try? JSONDecoder().decode(Wrap.self, from: data)` → `wrap.data` → 否则 `SyncError.decode`
2. `restore(_ payload:)` MVP：`_ = payload; try context.save()`（占位）
3. UI 层：`env.markSynced()`；message = "恢复成功"

### 错误处理

**代码入口：** `BackupSyncUseCase.SyncError`

| Case | 触发场景 | 用户可见提示 |
|------|---------|-------------|
| `.serverEmpty` | `AppSyncConfig.host.isEmpty` | 请先配置同步服务器地址 |
| `.network(let m)` | 预留网络错误封装（当前未主动抛，`URLSession` 原生错误也会经 `error.localizedDescription` 呈现） | 网络错误：… |
| `.decode` | download 返回体解码失败 / `data == nil` | 服务端返回数据无法解析 |

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
