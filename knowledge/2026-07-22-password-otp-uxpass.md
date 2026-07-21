# 密码 & 2FA · 交互与安全一轮完善（编辑 / 删除 / 复制反馈 / 明文查看 / 输入清空 / 扫码添加）

日期：2026-07-22
涉及文件：
- `personal-butler/Presentation/Views/SubPages/PasswordView.swift`（重构）
- `personal-butler/Presentation/Components/QRCodeScannerView.swift`（新增）
- `personal-butler/Core/Utils/OTPAuthURL.swift`（新增）
- `docs/module-spec/module-password-otp-spec.md`（反哺）

## 背景

MVP 首版密码/2FA 模块只有"新增 + 查看"，一次连做 6 项体验补齐：

1. 卡片点击 → 编辑弹窗；卡片左滑 → 删除（对齐日程/纪念日）
2. 三处复制按钮（账号 / 密码 / 2FA 验证码）都要有"复制成功"反馈
3. 密码编辑页要能查看明文
4. 账号 / 密码长串输入要能一键清空
5. 2FA 验证器改为**默认打开**（用户高频功能，放左侧默认 tab）
6. 2FA 新增只支持扫码（不再手输 Base32），编辑只允许改展示字段（issuer / accountName），secret 相关全部隐藏

## 决策

### 编辑 / 删除：复用 `SwipeToDeleteRow`

- `EditPasswordSheet(account:)` / `EditOTPSheet(account:)` 与日程/纪念日同款"nil = 新增，非 nil = 编辑"套路，`init` 里把 model 字段拷贝到 `@State`
- 密码 / 2FA 两种卡片都包 `SwipeToDeleteRow`：点击 → 编辑；左滑 → 露出红色删除按钮 → `.alert` 二次确认
- **敏感数据兜底**：删除时必须先 `KeychainManager.delete(...)` 清明文，再 `context.delete(...)`
- 卡片上原有的内部按钮（👁️ / 📋）用 `.buttonStyle(.plain)` 优先消费点击，天然不会误触 SwipeRow 的 `onTap`

### 三处复制统一走 `copyToPasteboard(_ text: String, label: String)`

- 集中在父视图 `PasswordView`：写剪贴板 + `UIImpactFeedbackGenerator(.light)` 轻触反馈 + 底部黑色胶囊 toast（`checkmark.circle.fill` + "\(label)已复制"）
- 子组件 `PasswordCardView` / `OTPCodeCell` 通过 `let onCopy: (String, String) -> Void` 注入，不再持有 `UIPasteboard.general` 引用
- toast 用 `.overlay(alignment: .bottom)` 挂在整个 `ZStack` 之上，切 tab 也能看到；`easeInOut` 0.2s 淡入，1.4s 后淡出
- 样式对齐 `MineView.showToast`（黑色 78% 不透明胶囊 + 白字 + 20pt 圆角）

### 密码编辑页明文查看

- `EditPasswordSheet` 加 `@State revealPassword: Bool`，密码行用 `Group { if reveal { TextField } else { SecureField } }`
- 明文态关掉 `textInputAutocapitalization` + `autocorrectionDisabled`，避免密码里的字符被系统改写
- 门禁没加二次生物识别：进 `PasswordView` 已过一次页面级识别，编辑页复用这层门禁；如后续要"编辑密码需再验一次"可在 `EditPasswordSheet.task` 里加

### 长串输入清空按钮

- 抽 `clearButton(for: Binding<String>, accessibility:)`，仅当绑定文本非空时渲染，样式对齐 iOS 系统搜索栏（`xmark.circle.fill` + `#C4C7CC`）
- 账号行：清空 + 关自动大小写/纠正
- 密码行：清空按钮放在 👁️ 显隐按钮左侧，语义顺序 = "先清空 → 再决定要不要看"
- 平台名（`platform`）没加清空 —— 它是短品牌名，加了反而拥挤

### 2FA tab 顺序对调

- `SegmentedPill` 从 `[(.password, "密码"), (.otp, "2FA")]` 改为 `[(.otp, "2FA 验证器"), (.password, "密码")]`
- `@State var tab: Tab = .otp`，进页面直接落在 2FA
- FAB `if tab == .password ... else ...` 逻辑无关顺序，不用改

### 2FA：新增只扫码，编辑只改展示字段

**为什么砍手输 Base32：**

- 手输 Base32 密钥体验差 + 极易出错（大小写/字符集混淆）
- 明文密钥在剪贴板 / 输入法记忆里的暴露面比"扫码一次性写入 Keychain"大得多

**扫码链路：**

- `OTPScanSheet` = 全屏 `AVCaptureSession` 预览 + 中间白框取景区（`CAShapeLayer` evenOdd 挖洞）
- `QRCodeScannerView` 用 `UIViewControllerRepresentable` 包一层 `AVCaptureMetadataOutput`，`metadataObjectTypes = [.qr]`
- 命中一次后 `didFire = true` 防抖，避免连帧重复触发
- 主线程回调里 `UIImpactFeedbackGenerator(.light).impactOccurred()` + `dismiss()`

**otpauth 解析：**

- 新增 `Core/Utils/OTPAuthURL.swift`：`OTPAuthURL.parse(_ raw:)`
- 只认 `scheme == otpauth && host == totp`；`hotp` 与 `otpauth-migration` 不支持
- label 兼容 `Issuer:account` 和 query 里 `issuer=` 两种（同时出现优先 query）
- secret 归一：去空格 + 大写；**不做 Base32 合法性校验**（非法字符最终 `OTPGenerator.totp` 返回 `"------"`，UI 不崩）
- `period` / `digits` 未指定回退 30 / 6

**兜底："粘贴 otpauth 链接"入口：**

- 右上角 `link` 图标 + 相机失败降级页都能触发 Alert 里的 `TextField("otpauth://totp/...")`
- 应对场景：相机权限被拒、二维码只有复制链接、开发时模拟器无摄像头

**编辑收窄：**

- `EditOTPSheet(account: OTPAccount)` 从签名上就消除新增入口（`OTPAccount` 非可选）
- Form 只剩 `issuer` / `accountName` 两个 `TextField`，Base32 密钥输入行整段删除
- `save()` 不再触碰 Keychain，避免误改密钥导致验证码永久失效
- 底部说明改为："密钥通过扫码添加后不可修改，仅存于 iOS Keychain。如需替换密钥，请删除后重新扫码添加。"

## 踩坑

- **`AVCaptureMetadataOutput.setMetadataObjectsDelegate` 必须在 `session.addOutput` 之后**：SDK 校验 output 已挂到 session；顺序反了会 crash 或 silently no-op
- **`session.startRunning` 必须放到后台队列**：否则会在 iOS 17+ 触发一个诊断 warning，UI 也会短暂卡顿；用 `DispatchQueue.global(qos: .userInitiated).async` 起
- **手动 `_password = State(initialValue: KeychainManager.load(...) ?? "")` 会在 sheet 复用时保留残留**：SwiftUI 的 `sheet(item:)` 每次 dismiss 后组件销毁，下次呈现重新 `init`，实测不会残留；但如果改成 `sheet(isPresented:)` + 外部持有 model 就要小心
- **`clearButton` 用 `@ViewBuilder` + `if !text.isEmpty`**：不能返回 `EmptyView` 分支写在 `HStack` 里，`if` 判空才是"根本不布局"
- **`toolbarColorScheme(.dark, for: .navigationBar)` + `toolbarBackground(.hidden)`**：黑底扫码页导航栏文字变白，视觉才协调；只设一个都不够
- **`OTPAuthURL.parse` 不校验 Base32 合法性**：故意留白；一旦校验，某些扩展字符集的 issuer 会被拒。代价是"扫到假二维码也能保存"，但下一次刷验证码显示 `------`，用户自然会删掉重扫

## 验证

- 密码 tab：点卡片 → 编辑弹窗预填明文 + 分类；左滑 → 红色删除；`alert` 确认后 SwiftData 行 + Keychain 明文一起删
- 三处 📋：点击都出黑色胶囊 toast，1.4s 后消失，UIPasteboard 内容匹配
- 密码编辑页：默认 `SecureField`，点 👁️ 变 `TextField` 展示明文；账号 / 密码非空时右侧显示 `xmark.circle.fill`，点击清空
- 进入密码模块首帧落在 "2FA 验证器"
- FAB "+"（2FA tab）→ 弹全屏扫码页；扫 GitHub 生成的 `otpauth://totp/GitHub:user?secret=...` 后自动落库、跳回列表、每秒刷新验证码
- 相机权限拒绝 → 降级页 "无法访问相机" + "手动粘贴 otpauth 链接" 按钮；粘贴走同一条解析入口
- 无效链接（例如 `otpauth://hotp/...` 或缺 secret）→ 顶部弹 "链接不是有效的 otpauth 二维码"，扫码器继续工作
- 编辑 2FA：只见到 issuer / accountName 两行输入 + 底部说明；改完保存不触碰 Keychain，验证码继续刷新

## 复用点

- **`SwipeToDeleteRow` 已经跨 3 个 SubPage 复用**（Schedule / Anniversary / Password）：任何 ScrollView + VStack 结构的列表都能套；父视图 `openSwipeId` + 空白 tap 收起 + 切分段 `onChange` 收起是标配组合
- **`copyToPasteboard(_:label:)` + `.overlay(alignment: .bottom)` toast 模式**：适合所有"点按钮做点小事"的即时反馈；MineView 的 `showToast` 是同源实现，可以在下次触发相似需求时抽成 View Modifier
- **`QRCodeScannerView`**：其它需要扫码的场景（例如"扫菜谱二维码"）可以直接复用，`onDetect` 里跑各自的解析
- **`OTPAuthURL`**：以后要支持"从其它 authenticator 导出的 URL 列表"批量导入时，`parse` 是现成入口

## TODO / 后续

- 明文密码在 SwiftUI `TextField` 里会走系统键盘 → 键盘缓存可能是残留通道（AGENTS.md §5 已知取舍）。若接入 `AutoFill Credential Provider` 后可考虑用 `.textContentType(.password)` 让系统托管
- Base32 严格校验开关（默认关，保留兼容；出现"扫到但算不出"用户反馈时再开）
- Google Authenticator 迁移 URL（`otpauth-migration://offline?data=...`）解析：需要 protobuf 反序列化，目前不支持

## 引用

- 项目规范：[[AGENTS]] § 5 敏感操作红线 · § 6 编码约定
- 相关 case：`knowledge/2026-07-21-schedule-edit-delete.md`（`SwipeToDeleteRow` 的最初实现）
- Spec：`docs/module-spec/module-password-otp-spec.md`
- RFC：`RFC 6238`（TOTP）、`otpauth URL format`（Google Authenticator KeyUriFormat wiki）
