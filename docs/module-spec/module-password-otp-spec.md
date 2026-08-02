# PersonalButler · 密码 & 2FA · 模块级 SPEC

> 模块职责：本地私密密码库 + 内置 2FA（TOTP）验证器。**敏感数据（密码明文 / TOTP 密钥）直接落 SwiftData**（`passwordPlain` / `secretPlain` 字段），不再走 Keychain。进入模块与查看明文均强制生物识别。

## 1. 范围与边界

本模块负责：

- 密码账号 CRUD（新增 / 编辑 / 删除；左滑删除 + 二次确认）
- 分类筛选（社交/办公/金融/自定义）
- 明文查看与复制（点眼睛切换 + 复制按钮）
- 编辑密码时可切换明文查看，账号 / 密码支持一键清空
- 2FA 账号 CRUD（新增**仅支持扫码 `otpauth://totp/...` 二维码**；编辑仅允许改 issuer / accountName；删除随 SwiftData 记录一起清理明文）
- TOTP 每秒刷新(RFC 6238，HMAC-SHA1，6 位数字，30s 周期)
- 点击复制按钮把当前 6 位验证码写入剪贴板 + 底部黑色胶囊 toast 反馈
- 进入页面 / 恢复到前台时的**生物识别校验**
- 进入密码模块默认落在「2FA 验证器」tab（高频使用）

不覆盖:

- TOTP 密钥的服务端提供（仅本机 + 用户自建局域网同步）
- 密码的自动填充（AutoFill Credential Provider Extension，未启用）
- Google Authenticator 迁移 URL（`otpauth-migration://offline?data=...`）解析
- 密码强度评估、生成随机密码
- 2FA secret 编辑（一次性写入 SwiftData，之后不可改；如需替换需删除后重扫）

## 2. 核心概念

### PasswordAccount

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `platform` | String | 平台名（微信 / 招商银行 / …） |
| `account` | String | 账号（可含掩码） |
| `typeText` | String | 展示辅文（"社交 · 常用"） |
| `category` | Enum | 分类，决定卡片渐变色 |
| `passwordPlain` | String | **密码明文**（v5 起直接落 SwiftData，App 不连外网） |
| `passwordKeychainKey` | String | 历史 Keychain key，已废弃保留兼容；新数据写空串 |
| `updatedAt` | Date | 排序依据（倒序） |
| `isDemo` | Bool | 首启灌入的示例数据标记，清理 Demo 时按此过滤 |

明文直接从 `account.passwordPlain` 读出，无需走 Keychain。

### OTPAccount

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `issuer` | String | 服务商（GitHub / Google） |
| `accountName` | String | 账号名（邮箱等） |
| `secretPlain` | String | **TOTP Base32 密钥明文**（v5 起直接落 SwiftData） |
| `secretKeychainKey` | String | 历史 Keychain key，已废弃保留兼容；新数据写空串 |
| `period` | Int | 周期秒（默认 30） |
| `digits` | Int | 位数（默认 6） |
| `order` | Int | 列表排序（MVP 未提供拖拽排序 UI） |
| `isDemo` | Bool | 首启灌入的示例数据标记，清理 Demo 时按此过滤 |

Base32 密钥直接从 `account.secretPlain` 读出，无需走 Keychain。

### Keychain 迁移（一次性，冷启触发）

`PersonalButlerApp.migrateKeychainToSwiftData` 在 bootstrap 里调用一次：

- 遍历本地 `PasswordAccount` / `OTPAccount`
- 若 `passwordPlain` / `secretPlain` 为空，且 `passwordKeychainKey` / `secretKeychainKey` 非空 → 从 Keychain 读明文回填到 SwiftData 字段
- 迁移成功的 key 立即从 Keychain 删除，避免残留孤儿密钥
- 幂等：`passwordPlain` 已有值则跳过

### 生物识别门禁

- 进入 `PasswordView` 时先展示锁定态；`.task` 内 `await LocalAuthService.authenticate(reason: "查看密码需要生物识别")`
- 通过 → `authed = true` → 显示密码/2FA 列表 + FAB
- 未通过 / 用户拒绝 → 停留在锁定态；用户可点击「解锁」重试
- 模拟器无生物识别设备 → 自动返回 true（开发兜底）

### 卡片渐变

由 `PasswordAccount.category` 决定：

| 分类 | 渐变 | 边框 | tint |
|------|------|------|------|
| `.social` / `.custom`（默认） | `#F4F7FE → #E9EEFB` 蓝 | `#DDE4F5` | `primary` |
| `.finance` | `#F6F3FC → #ECE5F7` 紫 | `#E0D7EE` | `#8B6DBE` |
| `.office` | `#F0FBF5 → #E1F1E8` 绿 | `#CFE7D9` | `success` |

## 3. 代码边界与入口

| 入口/职责 | 文件 | 说明 |
|-----------|------|------|
| 页面入口 | `Presentation/Views/SubPages/PasswordView.swift` · `PasswordView` | `AppRouter.open("password")` 触发；默认 `tab = .otp` |
| 分段切换 | `PasswordView.tab: Tab (.otp / .password)` + `SegmentedPill` | 顺序：2FA 在左（默认），密码在右 |
| 密码卡片 | `PasswordView.swift` · `PasswordCardView` | 显隐 + 复制；包 `SwipeToDeleteRow` |
| OTP 卡片 | `PasswordView.swift` · `OTPCodeCell` | 定时刷新；右侧独立复制按钮；包 `SwipeToDeleteRow` |
| 左滑组件 | `Presentation/Components/SwipeToDeleteRow.swift` | 跨 Schedule/Anniversary/Password 复用 |
| 新增 / 编辑密码 | `PasswordView.swift` · `EditPasswordSheet(account:)` | `nil` = 新增，非 `nil` = 编辑；密码行支持显隐 + 清空 |
| 新增 2FA（扫码） | `PasswordView.swift` · `OTPScanSheet` | 相机扫 `otpauth://totp/...`；右上角 `link` 图标兜底"手动粘贴链接" |
| 编辑 2FA | `PasswordView.swift` · `EditOTPSheet(account:)` | 参数为**非可选** `OTPAccount`；只能改 issuer / accountName |
| 扫码组件 | `Presentation/Components/QRCodeScannerView.swift` | 纯 `AVFoundation`，无三方；命中一次自动防抖 |
| otpauth 解析 | `Core/Utils/OTPAuthURL.swift` · `OTPAuthURL.parse` | 兼容 label 内 `Issuer:account` + query `issuer=` |
| 复制反馈 | `PasswordView.swift` · `copyToPasteboard(_:label:)` | 集中入口：`UIPasteboard` + 轻触反馈 + 底部黑色胶囊 toast |
| Keychain（仅迁移用） | `Core/Utils/KeychainManager.swift` | `save / load / delete`；v5 起业务路径不再调用，仅 `PersonalButlerApp.migrateKeychainToSwiftData` 用于回填老用户数据 |
| TOTP 生成 | `Core/Utils/OTPGenerator.swift` | HMAC-SHA1 + Base32 解码 |
| 生物识别 | `Core/Auth/LocalAuthService.swift` | `deviceOwnerAuthentication` |

## 4. 核心场景

### 进入密码库门禁

**代码入口：** `PasswordView.swift` · `.task { authed = await LocalAuthService.authenticate(...) }`

**业务规则：**

- 首次进入必须通过生物识别（面容/密码）
- 未通过时展示"密码库已锁定"占位 + 手动"解锁"按钮
- 通过后展示内容 + FAB；FAB 根据当前 tab 决定新增密码 or 新增 OTP

**实现逻辑：**

1. `@State private var authed = false`
2. `.task { authed = await LocalAuthService.authenticate(reason: "查看密码需要生物识别") }`
3. `Group { authed ? content : lockScreen }`
4. `lockScreen` 按钮：`Task { authed = await LocalAuthService.authenticate(...) }` 重试

### 密码列表 + 分类筛选

**代码入口：** `PasswordView.swift` · `content`（`tab == .password` 分支） + `filteredPwds`

**业务规则：**

- 数据源 `@Query(sort: \PasswordAccount.updatedAt, order: .reverse)`
- 分类：`全部 / 社交 / 办公 / 金融 / 自定义`
- "全部"（`filterIndex == 0`）→ 不过滤
- 其他 → `accounts.filter { $0.category == cat }`

**实现逻辑：**

1. `HorizontalTagBar(items: categories.map { $0.0 }, selectedIndex: $filterIndex)`
2. `filteredPwds` 计算
3. `ScrollView { LazyVStack { ForEach(filteredPwds) { PasswordCardView(account: $0) } } }`

### 密码卡片显隐 & 复制

**代码入口：** `PasswordView.swift` · `PasswordCardView` + 父视图 `copyToPasteboard(_:label:)`

**业务规则：**

- 默认展示掩码 `••••••••`
- 点击 👁 图标 → toggle `reveal`；显示时直接读 `account.passwordPlain`
- 点击 📋 图标 → 复制明文到 `UIPasteboard.general`（无需先显示）；触发轻触反馈 + 底部黑色胶囊 toast "密码已复制"
- 账号列的 📋 → toast "账号已复制"
- 显示明文时字号 13pt（monospaced）；掩码时 15pt + `kerning(3)` 拉开点距
- 点击卡片主体（非 👁 / 📋 按钮）→ 弹出 `EditPasswordSheet(account:)` 编辑
- 卡片左滑 → 露出红色圆形删除按钮 → `.alert` 二次确认 → `context.delete(p)`（明文随记录一起删除）

**实现逻辑：**

1. 卡片包在 `SwipeToDeleteRow` 里，`onTap = { editingPwd = p }` / `onDelete = { pendingDeletePwd = p }`
2. `PasswordCardView` 接收 `let onCopy: (String, String) -> Void`；不直接持有 `UIPasteboard.general`
3. `copyToPasteboard(text, label)`（父视图集中入口）：
   - `UIPasteboard.general.string = text`
   - `UIImpactFeedbackGenerator(style: .light).impactOccurred()`
   - 设置 `@State toast = "\(label)已复制"`；1.4s 后 `withAnimation` 清空
4. toast UI 挂在整个 `ZStack.overlay(alignment: .bottom)`，切 tab 也能覆盖
5. 删除 alert 确认按钮：`context.delete(p)` → `save()`（不再调用 Keychain）

### 2FA 列表 & 定时刷新

**代码入口：** `PasswordView.swift` · `OTPCodeCell`

**业务规则：**

- 数据源 `@Query(sort: \OTPAccount.order)`
- 卡片右侧展示 6 位数字 + "N s 后刷新"
- 每 1 秒 `Timer.publish` tick → 重新计算 TOTP 与 remaining 秒数
- 右侧独立 📋 复制按钮（不再是点整行）→ 复制当前 code + toast "验证码已复制"
- 点击卡片主体 → 弹出 `EditOTPSheet(account:)` 编辑 issuer / accountName
- 卡片左滑 → 删除；明文随 `context.delete(o)` 一起删除

**实现逻辑：**

1. 卡片包在 `SwipeToDeleteRow` 里，`onTap = { editingOTP = o }`
2. `OTPCodeCell` 接收 `let onCopy: (String, String) -> Void`
3. `@State private var code = "------"`；`@State var remaining = 30`
4. `.onAppear { refresh() }` + `.onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }`
5. `refresh()`：
   - `guard !account.secretPlain.isEmpty else { code = "------"; return }`
   - `OTPGenerator.totp(secretBase32: account.secretPlain, period: account.period, digits: account.digits)`
   - `OTPGenerator.remainingSeconds(period:)`
6. 复制按钮：`Button { onCopy(code, "验证码") } label: { Image("doc.on.doc") }`

### TOTP 算法

**代码入口：** `Core/Utils/OTPGenerator.swift` · `totp(secretBase32:period:digits:at:)`

**业务规则：**

- 遵循 RFC 6238 TOTP，`counter = floor(unix_ts / period)`
- HMAC-SHA1(counter_be_uint64, base32_decoded_key)
- 动态截断（Dynamic Truncation, RFC 4226 §5.3）
- 结果对 `10^digits` 取模，左侧补 0 到 `digits` 位
- 解码失败或空密钥返回 `"------"`

**实现逻辑：**

1. `base32Decode(uppercased)`：忽略空格 / `=`，5bit 累加，每 8bit 输出一字节
2. `counter = UInt64(unix_ts) / period`，转 big endian
3. `HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: key))`
4. `offset = mac[mac.count-1] & 0x0f`
5. `bin = (mac[offset] & 0x7f) << 24 | mac[offset+1] << 16 | mac[offset+2] << 8 | mac[offset+3]`
6. `code = bin % 10^digits`；`String(format: "%0\(digits)d", code)`

### 新增 / 编辑密码

**代码入口：** `PasswordView.swift` · `EditPasswordSheet(account:)`

**业务规则：**

- `account == nil` → 新增；非 `nil` → 编辑（`init` 从 `account.passwordPlain` 预填明文密码，从 `PasswordAccount` 预填其它字段）
- 平台名空 → "未命名"
- 编辑时直接回写 `account.passwordPlain`；新增时构造 `PasswordAccount(passwordPlain: password)`
- 一次 `context.save()` 落盘，无 Keychain 调用
- 密码行支持明文查看（`@State revealPassword`，`SecureField` ↔ `TextField` 切换）；明文态关掉自动大小写化 + 自动纠正
- 账号 / 密码非空时右侧显示 `xmark.circle.fill` 一键清空（长串账号 / 密码高频需求）
- 平台名不加清空按钮（短品牌名，加了拥挤）

**实现逻辑：**

1. FAB → `showCreatePwd = true`；或点卡片 → `editingPwd = p`
2. Form：platform / account（清空） / password（`SecureField` ↔ `TextField` + 清空 + 显隐） / category
3. `save()`：
   - 编辑：回写 `p.passwordPlain = password` 等字段 → 刷新 `updatedAt`
   - 新增：`context.insert(PasswordAccount(platform:, account:, typeText:, category:, passwordPlain: password))`
4. `try? context.save()` → `dismiss()`

### 新增 2FA（扫码）

**代码入口：** `PasswordView.swift` · `OTPScanSheet` + `QRCodeScannerView` + `OTPAuthURL.parse`

**业务规则：**

- 仅支持通过扫二维码添加；**不再提供手输 Base32 表单**
- 二维码内容必须是 `otpauth://totp/...`（`hotp` 与 `otpauth-migration` 不支持）
- 解析 label 中 `Issuer:account` 或 query 里 `issuer=`；两者共存优先 query
- secret 归一：去空格 + 大写；**不做 Base32 合法性校验**（下游 `OTPGenerator.totp` 遇非法字符返回 `------`）
- `period` / `digits` 未指定回退 30 / 6
- 相机不可用（无权限 / 无设备）→ 降级页 + "手动粘贴 otpauth 链接" Alert 兜底
- 右上角 `link` 图标 → 触发同一个"粘贴链接" Alert（应对二维码只有复制链接的场景）
- 无效链接 → 顶部黑色胶囊 toast 提示，扫码器继续工作

**实现逻辑：**

1. FAB (2FA tab) → `showCreateOTP = true` → 全屏 `OTPScanSheet`
2. `QRCodeScannerView` 内部：
   - `AVCaptureSession` + `AVCaptureDeviceInput(video)` + `AVCaptureMetadataOutput`
   - `output.metadataObjectTypes = [.qr]`
   - `session.startRunning()` 放到 `DispatchQueue.global(qos: .userInitiated)` 后台队列
   - 命中一次后 `didFire = true` 防抖
3. `OTPAuthURL.parse(scannedString)` → 解析成功：
   - `context.insert(OTPAccount(issuer:, accountName:, secretPlain: parsed.secretBase32, period:, digits:))`
   - `UINotificationFeedbackGenerator(.success)` + `dismiss()`
4. 解析失败 → `showError("链接不是有效的 otpauth 二维码")` 2s 后自动消失

### 编辑 2FA（仅展示字段）

**代码入口：** `PasswordView.swift` · `EditOTPSheet(account: OTPAccount)`

**业务规则：**

- 参数为**非可选** `OTPAccount`，从签名上禁止新增走这里
- 只允许改 `issuer` / `accountName`；Base32 密钥输入框、`period` / `digits` 相关字段**全部隐藏**
- 保存时不触碰 `secretPlain`，避免误改导致验证码永久失效
- 底部说明："密钥通过扫码添加后不可修改，仅存于本机 SwiftData。如需替换密钥，请删除后重新扫码添加。"

**实现逻辑：**

1. 点 OTP 卡片 → `editingOTP = o` → `.sheet(item:)` 呈现
2. Form：只有两个 `TextField(issuer)` / `TextField(accountName)`；后者关自动大小写 + 纠正
3. `save()`：`o.issuer = ...` / `o.accountName = ...` → `context.save()`

### 删除密码 / 2FA

**代码入口：** `PasswordView.swift` · `pendingDeletePwd` / `pendingDeleteOTP` + `.alert(...)`

**业务规则：**

- 左滑 → 露出圆形红色删除按钮；点击 → 二次 `.alert` 确认
- 确认后直接 `context.delete(p)` / `context.delete(o)`；明文随 SwiftData 记录一起删除，不再单独清理 Keychain
- 确认或取消后收起左滑态（`openSwipeId = nil`）

**实现逻辑：**

1. `SwipeToDeleteRow.onDelete = { pendingDeletePwd = p }` / `{ pendingDeleteOTP = o }`
2. `.alert("删除该密码？", isPresented: Binding(...))`：
   - 取消 → `pendingDelete? = nil`
   - 删除 → `context.delete(...)` → `save()` → `openSwipeId = nil`

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/PasswordView.swift`
  - `personal-butler/Presentation/Components/QRCodeScannerView.swift`
  - `personal-butler/Presentation/Components/SwipeToDeleteRow.swift`
  - `personal-butler/Domain/Models/PasswordAccount.swift`
  - `personal-butler/Domain/Models/OTPAccount.swift`
  - `personal-butler/Core/Utils/KeychainManager.swift`
  - `personal-butler/Core/Utils/OTPGenerator.swift`
  - `personal-butler/Core/Utils/OTPAuthURL.swift`
  - `personal-butler/Core/Auth/LocalAuthService.swift`
- 规范：
  - RFC 6238：https://datatracker.ietf.org/doc/html/rfc6238 （TOTP）
  - RFC 4226 §5.3：https://datatracker.ietf.org/doc/html/rfc4226#section-5.3 （HOTP dynamic truncation）
  - RFC 4648 §6：https://datatracker.ietf.org/doc/html/rfc4648#section-6 （Base32）
  - Google Authenticator KeyUriFormat：https://github.com/google/google-authenticator/wiki/Key-Uri-Format
- 文档：
  - `docs/PRD.md § 9 密码 & 2FA`
  - `knowledge/2026-07-22-password-otp-uxpass.md`（本轮迭代沉淀）
