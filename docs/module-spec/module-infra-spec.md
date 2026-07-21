# PersonalButler · Core 通用能力 · 模块级 SPEC

> 模块职责：为所有业务模块提供**无业务耦合**的横切能力：敏感数据存储（Keychain）、生物识别、TOTP 生成、日期计算、本地通知、UI 常量、Swift 扩展。是全 App 的基础底座。

## 1. 范围与边界

本模块负责：

- Keychain 读写（`KeychainManager`）
- 生物识别（`LocalAuthService`，面容 / 密码）
- TOTP 生成（`OTPGenerator`，RFC 6238）
- 日期业务计算（`DateCalculator`：每年重复倒计时、累计天数、农历字串、相对时间）
- 本地通知调度（`NotificationManager`，未在业务模块 MVP 中接入）
- UI 常量（`UIConstant`：卡片尺寸、圆角、间距）
- Swift 扩展：`Color+Ext`（HEX 便捷构造）、`Date+Ext`（`startOfDay/endOfDay/hourMinute/daysBetween`）、`View+Ext`

不覆盖：

- 任何业务实体、任何页面 UI
- `SyncPayload` DTO（属备份同步模块）
- SwiftData `ModelContainer` 初始化（属 app-shell）

## 2. 核心概念

### KeychainManager

`kSecClassGenericPassword`；`service = "org.lewislk.personal-butler"`；`account = key`（业务自选 key，如 `pwd.<uuid>` / `otp.<uuid>`）。

`kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`：设备解锁一次后即可读取；卸载 App 时系统自动清除；不跨设备同步。

写入前先删旧值（`SecItemDelete` 忽略结果），再 `SecItemAdd`。

### LocalAuthService

统一使用 `LAPolicy.deviceOwnerAuthentication`（可回落到设备密码，比 `deviceOwnerAuthenticationWithBiometrics` 更兼容）。

模拟器 / 无生物识别设备（`canEvaluatePolicy` 返回 false）→ 直接返回 `true` 放行，避免开发阻塞。这个"开发兜底"是**故意的**，需要在生产版本收紧策略时改动此文件。

### OTPGenerator

- 算法：HMAC-SHA1（`Insecure.SHA1`，CryptoKit）
- 密钥编码：Base32（`A-Z 2-7`，忽略空格与 `=`）
- 输出：`String(format: "%0\(digits)d", bin % 10^digits)`
- 时间基准：`Date.timeIntervalSince1970 / period`

`remainingSeconds(period:)` = `period - unix_ts % period`。

### DateCalculator

- `daysUntilNextYearly(from:isLunar:)`：以今年为基准的月/日构造下次发生日，过期取明年；农历切换 `Calendar(.chinese)`
- `cumulativeDays(from:)`：`startOfDay(now) - startOfDay(start)` 的 `.day` + 1（含今天）
- `lunarString(from:)`：`Calendar(.chinese) + DateFormatter locale zh_CN + "MMMMd日"` → `农历 · 冬月廿三`
- `gregorianDateLabel(_:)`：`公历 · 7月23日`
- `relativeLabel(_:)`：`今天 HH:mm` / `明天 HH:mm` / `EEEE HH:mm` / `N 天后`

### Date+Ext

| 属性 / 方法 | 用途 |
|-------------|------|
| `startOfDay` | 当日 0 点 |
| `endOfDay` | 当日 23:59:59（业务使用，实现见文件） |
| `hourMinute` | `HH:mm` 字符串 |
| `daysBetween(_:)` | 两个日期相差的整天数 |

### NotificationManager

对 `UNUserNotificationCenter` 的极薄封装：

- `requestAuth() async -> Bool`
- `schedule(id:title:body:at:)`：按年月日时分组件构造 `UNCalendarNotificationTrigger`，不重复
- `cancel(id:)`

**当前 MVP 未在日程/纪念日业务代码中主动调用**（PRD 后续会补齐"提前 N 分钟/N 天推送"逻辑）。

## 3. 代码边界与入口

| 能力 | 文件 | 关键 API |
|------|------|---------|
| Keychain | `Core/Utils/KeychainManager.swift` | `save(_:for:) -> Bool` / `load(_) -> String?` / `delete(_)` |
| 生物识别 | `Core/Auth/LocalAuthService.swift` | `authenticate(reason:) async -> Bool` |
| TOTP | `Core/Utils/OTPGenerator.swift` | `totp(secretBase32:period:digits:at:)` / `remainingSeconds(period:at:)` |
| 日期 | `Core/Utils/DateCalculator.swift` | `daysUntilNextYearly` / `cumulativeDays` / `lunarString` / `gregorianDateLabel` / `relativeLabel` |
| 通知 | `Core/Utils/NotificationManager.swift` | `requestAuth` / `schedule` / `cancel` |
| UI 常量 | `Core/Constants/UIConstant.swift` | 圆角 / FAB 尺寸 / 间距 |
| 扩展 | `Core/Extensions/Color+Ext.swift` / `Date+Ext.swift` / `View+Ext.swift` | HEX、Date 便捷、View 组合 |

## 4. 核心场景

### 存 / 读密码明文

**代码入口：** `KeychainManager.swift` · `save / load`

**业务规则：**

- 一个 `key` 对应一个"密码或密钥字符串"；`@Model` 里只存这个 key
- 保存前先删同 key 的旧值（防"重复添加"报错）
- 可访问性：`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（重启后需一次解锁；不参与 iCloud 同步）

**实现逻辑：**

1. `save(_ value: String, for key: String)`:
   - `data = value.data(using: .utf8)`
   - `SecItemDelete({class, service, account: key})` （忽略返回）
   - `SecItemAdd({class, service, account, data, accessible: AfterFirstUnlockThisDeviceOnly})`
   - 返回 `status == errSecSuccess`
2. `load(_ key: String)`:
   - `SecItemCopyMatching({class, service, account, returnData: true, matchLimit: one})`
   - 成功 → `String(data: data, encoding: .utf8)`
3. `delete(_ key: String)`:
   - `SecItemDelete({class, service, account})`

### 生物识别校验

**代码入口：** `LocalAuthService.swift` · `authenticate(reason:)`

**业务规则：**

- 敏感操作前必调；`reason` 会显示在系统弹窗中
- 支持面容 / 指纹 / 设备密码回落
- 模拟器 / 无生物识别设备 → 直接返回 `true`（开发兜底）

**实现逻辑：**

1. `let ctx = LAContext()`
2. `guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }`
3. `withCheckedContinuation { cont in ctx.evaluatePolicy(...) { ok, _ in cont.resume(returning: ok) } }`

### 生成 TOTP

**代码入口：** `OTPGenerator.swift` · `totp(secretBase32:period:digits:at:)`

**业务规则、实现逻辑：** 详见 [module-password-otp-spec.md § "TOTP 算法"](./module-password-otp-spec.md#totp-算法)。

关键点：
- Base32 解码失败或空密钥返回 `"------"`，UI 不 crash
- `remainingSeconds` 简化为 `period - unix_ts % period`（下一次刷新的秒数）

### 纪念日倒计时计算

**代码入口：** `DateCalculator.swift` · `daysUntilNextYearly(from:isLunar:)`

**业务规则：**

- 只取原始 `date` 的月/日作为周期基准，年份自动调整为今年（或明年，若已过）
- 农历用 `Calendar(identifier: .chinese)` 换算；公历用 `.gregorian`
- 天数使用 `Calendar.current.startOfDay(for: today)` 到目标日期的 `daysBetween`（今日返回 0）

**实现逻辑：**

1. `cal = Calendar(identifier: isLunar ? .chinese : .gregorian)`
2. `today = Calendar.current.startOfDay(for: now)`
3. 抽取 `[.month, .day]`；补 `year = 今年`
4. `next = cal.date(from: comps)`；若 `next < today` → `year += 1` 重算
5. `return today.daysBetween(next)`

### 累计天数

**代码入口：** `DateCalculator.swift` · `cumulativeDays(from:)`

**实现逻辑：**

```swift
let a = Calendar.current.startOfDay(for: start)
let b = Calendar.current.startOfDay(for: Date())
return (Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0) + 1
```

`+ 1` 表示起始日算第 1 天。

### 相对时间标签

**代码入口：** `DateCalculator.swift` · `relativeLabel(_:)`

**业务规则：**

- 用于主页近期待办 / 日程等场景的时间列
- 距今 0 天 → "今天 HH:mm"
- 1 天 → "明天 HH:mm"
- 2-6 天 → "EEEE HH:mm"（本周几）
- 7+ → "N 天后"

### 本地通知调度（预留能力）

**代码入口：** `NotificationManager.swift`

**业务规则（预留）：**

- 业务层未来在新增日程 / 纪念日时调用 `schedule(id:title:body:at:)`
- `id` 建议使用实体 UUID string，方便 `cancel(id:)`
- 用户改期时先 cancel 再 schedule

当前 MVP：能力就绪，业务代码未调用。

## 5. 参考资料

- 代码：
  - `personal-butler/Core/Utils/KeychainManager.swift`
  - `personal-butler/Core/Auth/LocalAuthService.swift`
  - `personal-butler/Core/Utils/OTPGenerator.swift`
  - `personal-butler/Core/Utils/DateCalculator.swift`
  - `personal-butler/Core/Utils/NotificationManager.swift`
  - `personal-butler/Core/Constants/UIConstant.swift`
  - `personal-butler/Core/Extensions/Color+Ext.swift`
  - `personal-butler/Core/Extensions/Date+Ext.swift`
  - `personal-butler/Core/Extensions/View+Ext.swift`
- Apple 文档：
  - Keychain Services: https://developer.apple.com/documentation/security/keychain_services
  - LocalAuthentication `LAContext`: https://developer.apple.com/documentation/localauthentication/lacontext
  - CryptoKit HMAC: https://developer.apple.com/documentation/cryptokit/hmac
  - UNUserNotificationCenter: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- 规范：
  - RFC 6238 TOTP: https://datatracker.ietf.org/doc/html/rfc6238
  - RFC 4648 Base32: https://datatracker.ietf.org/doc/html/rfc4648
