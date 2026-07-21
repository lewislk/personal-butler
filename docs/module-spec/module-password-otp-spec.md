# PersonalButler · 密码 & 2FA · 模块级 SPEC

> 模块职责：本地私密密码库 + 内置 2FA（TOTP）验证器。**所有敏感数据（密码明文 / TOTP 密钥）仅存 Keychain**，SwiftData 只存元数据 + Keychain key。进入模块与查看明文均强制生物识别。

## 1. 范围与边界

本模块负责：

- 密码账号 CRUD（MVP：新增；编辑/删除后续）
- 分类筛选（社交/办公/金融/自定义）
- 明文查看与复制（点眼睛切换 + 复制按钮）
- 2FA 账号 CRUD（MVP：手动输入 Base32；扫码导入留待二期）
- TOTP 每秒刷新（RFC 6238，HMAC-SHA1，6 位数字，30s 周期）
- 点击 OTP cell 复制当前 6 位到剪贴板
- 进入页面 / 恢复到前台时的**生物识别校验**

不覆盖：

- TOTP 密钥的服务端提供 / 云端同步（仅本机 Keychain）
- 密码的自动填充（AutoFill Credential Provider Extension，未启用）
- otpauth:// 二维码扫描（PRD 二期）
- 密码强度评估、生成随机密码

## 2. 核心概念

### PasswordAccount

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `platform` | String | 平台名（微信 / 招商银行 / …） |
| `account` | String | 账号（可含掩码） |
| `typeText` | String | 展示辅文（"社交 · 常用"） |
| `category` | Enum | 分类，决定卡片渐变色 |
| `passwordKeychainKey` | String | Keychain 中密码明文的 key（`pwd.<uuid>`） |
| `updatedAt` | Date | 排序依据（倒序） |

明文不在此存储，通过 `KeychainManager.load(passwordKeychainKey)` 取出。

### OTPAccount

| 字段 | 类型 | 业务含义 |
|------|------|---------|
| `issuer` | String | 服务商（GitHub / Google） |
| `accountName` | String | 账号名（邮箱等） |
| `secretKeychainKey` | String | Keychain 中 Base32 密钥的 key（`otp.<uuid>`） |
| `period` | Int | 周期秒（默认 30） |
| `digits` | Int | 位数（默认 6） |
| `order` | Int | 列表排序（MVP 未提供拖拽排序 UI） |

Base32 密钥不在此存储。

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
| 页面入口 | `Presentation/Views/SubPages/PasswordView.swift` · `PasswordView` | `AppRouter.open("password")` 触发 |
| 分段切换 | `PasswordView.tab: Tab (.password / .otp)` + `SegmentedPill` | 切换密码列表 vs OTP 列表 |
| 密码卡片 | `PasswordView.swift` · `PasswordCardView` | 显隐 + 复制 |
| OTP 卡片 | `PasswordView.swift` · `OTPCodeCell` | 定时刷新 |
| 新增密码 | `PasswordView.swift` · `CreatePasswordSheet` | FAB 触发（`tab == .password`） |
| 新增 2FA | `PasswordView.swift` · `CreateOTPSheet` | FAB 触发（`tab == .otp`） |
| Keychain | `Core/Utils/KeychainManager.swift` | `save / load / delete` |
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

**代码入口：** `PasswordView.swift` · `PasswordCardView`

**业务规则：**

- 默认展示掩码 `••••••••`
- 点击 👁 图标 → toggle `reveal`；显示时用 `KeychainManager.load(passwordKeychainKey)` 取明文
- 点击 📋 图标 → 复制明文到 `UIPasteboard.general`（无需先显示）
- 账号列也有复制按钮
- 显示明文时字号 13pt（monospaced）；掩码时 15pt + `kerning(3)` 拉开点距

**实现逻辑：**

1. `@State private var reveal = false`
2. row("密码", value: reveal ? load 明文 : "••••••••", trailingIcons: [👁 toggle, 📋 copy])
3. 复制按钮：直接 `if let plain = KeychainManager.load(...) { UIPasteboard.general.string = plain }`

### 2FA 列表 & 定时刷新

**代码入口：** `PasswordView.swift` · `OTPCodeCell`

**业务规则：**

- 数据源 `@Query(sort: \OTPAccount.order)`
- 卡片右侧展示 6 位数字 + "N s 后刷新"
- 每 1 秒 `Timer.publish` tick → 重新计算 TOTP 与 remaining 秒数
- 点击 cell → 复制当前 code 到剪贴板

**实现逻辑：**

1. `@State private var code = "------"`；`@State var remaining = 30`
2. `.onAppear { refresh() }`
3. `.onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }`
4. `refresh()`：
   - `guard let secret = KeychainManager.load(secretKeychainKey) else { return }`
   - `OTPGenerator.totp(secretBase32: secret, period: account.period, digits: account.digits)`
   - `OTPGenerator.remainingSeconds(period:)`
5. `.onTapGesture { UIPasteboard.general.string = code }`

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

### 新增密码

**代码入口：** `PasswordView.swift` · `CreatePasswordSheet`

**业务规则：**

- 平台名空 → "未命名"
- 保存前先生成 `key = "pwd." + UUID().uuidString`
- 用 `KeychainManager.save(password, for: key)` 写明文
- 再插入 `PasswordAccount(passwordKeychainKey: key, ...)`
- Keychain 与 SQLite 是**两次写入，无事务保证**；MVP 接受"极端场景下 keychain 已写、SQLite 未写"的孤儿密钥（占用极小）

**实现逻辑：**

1. FAB → `showCreatePwd = true`
2. Form: platform / account / password（SecureField） / category
3. 保存：keychain save → context insert → save → dismiss

### 新增 2FA

**代码入口：** `PasswordView.swift` · `CreateOTPSheet`

**业务规则：**

- Base32 密钥手动输入（大写化通过 `textInputAutocapitalization(.characters)`）
- 保存后立即出现在 OTP 列表；`OTPCodeCell.onAppear` 触发首帧计算
- 若密钥格式错误 → `OTPGenerator.totp` 返回 `"------"`，UI 不崩溃

**实现逻辑：**

1. FAB → `showCreateOTP = true`
2. Form: issuer / accountName / secret（Base32）
3. 保存：keychain save → `OTPAccount(secretKeychainKey: key)` → `context.insert` → `save`

## 5. 参考资料

- 代码：
  - `personal-butler/Presentation/Views/SubPages/PasswordView.swift`
  - `personal-butler/Domain/Models/PasswordAccount.swift`
  - `personal-butler/Domain/Models/OTPAccount.swift`
  - `personal-butler/Core/Utils/KeychainManager.swift`
  - `personal-butler/Core/Utils/OTPGenerator.swift`
  - `personal-butler/Core/Auth/LocalAuthService.swift`
- 规范：
  - RFC 6238：https://datatracker.ietf.org/doc/html/rfc6238 （TOTP）
  - RFC 4226 §5.3：https://datatracker.ietf.org/doc/html/rfc4226#section-5.3 （HOTP dynamic truncation）
  - RFC 4648 §6：https://datatracker.ietf.org/doc/html/rfc4648#section-6 （Base32）
- 文档：
  - `docs/PRD.md § 9 密码 & 2FA`
