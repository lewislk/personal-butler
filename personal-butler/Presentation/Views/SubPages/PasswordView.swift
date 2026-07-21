//
//  PasswordView.swift
//  密码记录（含 2FA 分段切换）
//

import SwiftUI
import SwiftData

struct PasswordView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PasswordAccount.updatedAt, order: .reverse) private var accounts: [PasswordAccount]
    @Query(sort: \OTPAccount.order) private var otps: [OTPAccount]

    enum Tab: Hashable { case password, otp }

    @State private var tab: Tab = .otp
    @State private var filterIndex: Int = 0
    @State private var authed = false
    @State private var showCreatePwd = false
    @State private var showCreateOTP = false
    @State private var editingPwd: PasswordAccount?
    @State private var editingOTP: OTPAccount?
    @State private var pendingDeletePwd: PasswordAccount?
    @State private var pendingDeleteOTP: OTPAccount?
    /// 当前处于展开态（已左滑露出删除按钮）的卡片 id；同一时刻最多一个
    @State private var openSwipeId: UUID?
    /// 复制成功提示（黑色胶囊 toast），nil 表示不展示
    @State private var toast: String?

    private let categories: [(String, PasswordCategory?)] = [
        ("全部", nil),
        ("社交", .social),
        ("办公", .office),
        ("金融", .finance),
        ("自定义", .custom)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if authed {
                    content
                } else {
                    lockScreen
                }
            }

            if authed {
                FABAddButton {
                    if tab == .password { showCreatePwd = true } else { showCreateOTP = true }
                }
            }
        }
        .navigationTitle("密码记录")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            authed = await LocalAuthService.authenticate(reason: "查看密码需要生物识别")
        }
        .sheet(isPresented: $showCreatePwd) { EditPasswordSheet(account: nil) }
        .sheet(isPresented: $showCreateOTP) { OTPScanSheet() }
        .sheet(item: $editingPwd) { p in EditPasswordSheet(account: p) }
        .sheet(item: $editingOTP) { o in EditOTPSheet(account: o) }
        .alert("删除该密码？",
               isPresented: Binding(get: { pendingDeletePwd != nil },
                                    set: { if !$0 { pendingDeletePwd = nil } })) {
            Button("取消", role: .cancel) { pendingDeletePwd = nil }
            Button("删除", role: .destructive) {
                if let p = pendingDeletePwd {
                    // 敏感数据：先清 Keychain 明文再删 SwiftData 行
                    KeychainManager.delete(p.passwordKeychainKey)
                    context.delete(p)
                    try? context.save()
                }
                pendingDeletePwd = nil
                openSwipeId = nil
            }
        } message: {
            Text(pendingDeletePwd.map { "「\($0.platform)」删除后不可恢复。" } ?? "")
        }
        .alert("删除该 2FA 账号？",
               isPresented: Binding(get: { pendingDeleteOTP != nil },
                                    set: { if !$0 { pendingDeleteOTP = nil } })) {
            Button("取消", role: .cancel) { pendingDeleteOTP = nil }
            Button("删除", role: .destructive) {
                if let o = pendingDeleteOTP {
                    KeychainManager.delete(o.secretKeychainKey)
                    context.delete(o)
                    try? context.save()
                }
                pendingDeleteOTP = nil
                openSwipeId = nil
            }
        } message: {
            Text(pendingDeleteOTP.map { "「\($0.issuer)」删除后不可恢复。" } ?? "")
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text(t).font(.system(size: 13))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.78)))
                .foregroundStyle(.white)
                .padding(.bottom, 32)
                .transition(.opacity)
            }
        }
    }

    /// 统一的"复制到剪贴板 + 成功反馈"入口：写入 UIPasteboard、给一次轻触反馈、
    /// 悬浮 1.4s 后自动消失。所有卡片里的复制按钮都走这里，样式与 MineView 的 toast 一致。
    fileprivate func copyToPasteboard(_ text: String, label: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) { toast = "\(label)已复制" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.2)) { toast = nil }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(AppColorTheme.primary)
            Text("密码库已锁定").font(.system(size: 15, weight: .medium))
            Button("解锁") {
                Task { authed = await LocalAuthService.authenticate(reason: "查看密码") }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var content: some View {
        VStack(spacing: 0) {
            SegmentedPill(items: [(Tab.otp, "2FA 验证器"), (Tab.password, "密码")],
                          selection: $tab)
                .padding(.horizontal, 16).padding(.top, 12)

            if tab == .password {
                HorizontalTagBar(items: categories.map { $0.0 }, selectedIndex: $filterIndex)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredPwds, id: \.id) { p in
                            pwdRow(p)
                        }
                    }
                    .padding(.top, 4)
                    Spacer(minLength: 80)
                }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(otps, id: \.id) { o in
                            otpRow(o)
                        }
                    }
                    .padding(.top, 12)
                    Spacer(minLength: 80)
                }
            }
        }
        .background(Color.white)
        // 点击任何空白区收起已展开的滑动行
        .simultaneousGesture(
            TapGesture().onEnded {
                if openSwipeId != nil {
                    openSwipeId = nil
                }
            }
        )
        // 切分段 / 切分类都顺手收起
        .onChange(of: tab) { _, _ in openSwipeId = nil }
        .onChange(of: filterIndex) { _, _ in openSwipeId = nil }
    }

    private func pwdRow(_ p: PasswordAccount) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(
                get: { openSwipeId == p.id },
                set: { openSwipeId = $0 ? p.id : nil }
            ),
            onTap: { editingPwd = p },
            onDelete: { pendingDeletePwd = p }
        ) {
            PasswordCardView(account: p, onCopy: copyToPasteboard)
                .padding(.horizontal, 16)
        }
    }

    private func otpRow(_ o: OTPAccount) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(
                get: { openSwipeId == o.id },
                set: { openSwipeId = $0 ? o.id : nil }
            ),
            onTap: { editingOTP = o },
            onDelete: { pendingDeleteOTP = o }
        ) {
            OTPCodeCell(account: o, onCopy: copyToPasteboard)
                .padding(.horizontal, 16)
        }
    }

    private var filteredPwds: [PasswordAccount] {
        guard let cat = categories[filterIndex].1 else { return accounts }
        return accounts.filter { $0.category == cat }
    }
}

// MARK: - 密码卡片
private struct PasswordCardView: View {
    let account: PasswordAccount
    /// 复制回调：(text, label) → 父视图统一写剪贴板 + 弹 toast
    let onCopy: (String, String) -> Void
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(account.platform)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColorTheme.text)
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tint.opacity(0.8))
                Spacer()
            }
            Text(account.typeText.isEmpty ? account.category.label : account.typeText)
                .font(.system(size: 11))
                .foregroundStyle(AppColorTheme.textSub)
                .padding(.top, 2)

            row(label: "账号", value: account.account, hidden: false,
                trailingIcons: [
                    ("doc.on.doc", { onCopy(account.account, "账号") })
                ])
                .padding(.top, 10)
            Divider().background(Color.black.opacity(0.06))
            row(label: "密码",
                value: reveal ? (KeychainManager.load(account.passwordKeychainKey) ?? "") : "••••••••",
                hidden: !reveal,
                trailingIcons: [
                    (reveal ? "eye.slash" : "eye", { reveal.toggle() }),
                    ("doc.on.doc", {
                        if let plain = KeychainManager.load(account.passwordKeychainKey) {
                            onCopy(plain, "密码")
                        }
                    })
                ])
        }
        .padding(14)
        .background(
            LinearGradient(colors: gradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
        .shadow(color: AppColorTheme.primary.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private var gradient: [Color] {
        switch account.category {
        case .finance: return [Color(hex: 0xF6F3FC), Color(hex: 0xECE5F7)]
        case .office:  return [Color(hex: 0xF0FBF5), Color(hex: 0xE1F1E8)]
        default:       return [Color(hex: 0xF4F7FE), Color(hex: 0xE9EEFB)]
        }
    }
    private var border: Color {
        switch account.category {
        case .finance: return Color(hex: 0xE0D7EE)
        case .office:  return Color(hex: 0xCFE7D9)
        default:       return Color(hex: 0xDDE4F5)
        }
    }
    private var tint: Color {
        switch account.category {
        case .finance: return Color(hex: 0x8B6DBE)
        case .office:  return AppColorTheme.success
        default:       return AppColorTheme.primary
        }
    }

    private func row(label: String, value: String, hidden: Bool,
                     trailingIcons: [(String, () -> Void)]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 11)).foregroundStyle(AppColorTheme.textSub)
                Text(value)
                    .font(.system(size: hidden ? 15 : 13, design: .monospaced))
                    .foregroundStyle(hidden ? AppColorTheme.textSub : AppColorTheme.text)
                    .kerning(hidden ? 3 : 0)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(trailingIcons.enumerated()), id: \.offset) { _, tuple in
                    Button(action: tuple.1) {
                        Image(systemName: tuple.0)
                            .font(.system(size: 12))
                            .foregroundStyle(AppColorTheme.textSub)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - 2FA cell
private struct OTPCodeCell: View {
    let account: OTPAccount
    let onCopy: (String, String) -> Void
    @State private var code = "------"
    @State private var remaining = 30

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.issuer).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColorTheme.text)
                Text(account.accountName).font(.system(size: 11)).foregroundStyle(AppColorTheme.textSub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(code)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColorTheme.primary)
                Text("\(remaining)s 后刷新")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColorTheme.textSub)
            }
            // 复制按钮：单独暴露一个可点区域，避免与"点击卡片进入编辑"冲突
            Button {
                onCopy(code, "验证码")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
        .onAppear { refresh() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        guard let secret = KeychainManager.load(account.secretKeychainKey) else { return }
        code = OTPGenerator.totp(secretBase32: secret, period: account.period, digits: account.digits)
        remaining = OTPGenerator.remainingSeconds(period: account.period)
    }
}

// MARK: - 新增 / 编辑密码
struct EditPasswordSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 传 nil 表示新增，传入实例表示编辑
    let account: PasswordAccount?

    @State private var platform: String
    @State private var accountName: String
    @State private var password: String
    @State private var category: PasswordCategory
    /// 是否显示密码明文；默认隐藏（SecureField），点小眼睛切换到普通 TextField
    @State private var revealPassword: Bool = false

    init(account: PasswordAccount?) {
        self.account = account
        _platform = State(initialValue: account?.platform ?? "")
        _accountName = State(initialValue: account?.account ?? "")
        // 编辑态预填明文，便于查看/修改；未修改直接保存则原样写回
        _password = State(initialValue: account.flatMap { KeychainManager.load($0.passwordKeychainKey) } ?? "")
        _category = State(initialValue: account?.category ?? .social)
    }

    private var isEditing: Bool { account != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("平台名（如 微信）", text: $platform)
                    HStack {
                        TextField("账号", text: $accountName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        clearButton(for: $accountName, accessibility: "清空账号")
                    }
                    HStack {
                        Group {
                            if revealPassword {
                                TextField("密码", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            } else {
                                SecureField("密码", text: $password)
                            }
                        }
                        clearButton(for: $password, accessibility: "清空密码")
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColorTheme.textSub)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(revealPassword ? "隐藏密码" : "显示密码")
                    }
                }
                Section {
                    Picker("分类", selection: $category) {
                        ForEach(PasswordCategory.allCases, id: \.self) { c in
                            Text(c.label).tag(c)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑密码" : "新增密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        let finalPlatform = platform.isEmpty ? "未命名" : platform
        if let p = account {
            KeychainManager.save(password, for: p.passwordKeychainKey)
            p.platform = finalPlatform
            p.account = accountName
            p.typeText = category.label
            p.categoryRaw = category.rawValue
            p.updatedAt = .init()
        } else {
            let key = "pwd." + UUID().uuidString
            KeychainManager.save(password, for: key)
            let p = PasswordAccount(platform: finalPlatform,
                                    account: accountName, typeText: category.label,
                                    category: category, passwordKeychainKey: key)
            context.insert(p)
        }
        try? context.save()
    }

    /// 输入框尾部的圆形"清空"按钮：仅当绑定文本非空时才出现，避免视觉冗余
    @ViewBuilder
    private func clearButton(for text: Binding<String>, accessibility: String) -> some View {
        if !text.wrappedValue.isEmpty {
            Button {
                text.wrappedValue = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: 0xC4C7CC))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibility)
        }
    }
}

// MARK: - 编辑 OTP（仅编辑，不支持新增；新增走 OTPScanSheet 扫码）
//
// 产品约束：
//  - 2FA 密钥（Base32 secret）通过扫码一次性写入 Keychain，之后视为不可变。
//  - 用户在这里只能修改「签发方」和「账号名」两个展示字段，避免误改导致验证码失效。
//
struct EditOTPSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 传入实例进入编辑；本组件不再接受新增
    let account: OTPAccount

    @State private var issuer: String
    @State private var accountName: String

    init(account: OTPAccount) {
        self.account = account
        _issuer = State(initialValue: account.issuer)
        _accountName = State(initialValue: account.accountName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务商（GitHub / Google...）", text: $issuer)
                    TextField("账号名", text: $accountName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section {
                    Text("密钥通过扫码添加后不可修改，仅存于 iOS Keychain。如需替换密钥，请删除后重新扫码添加。")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColorTheme.textSub)
                }
            }
            .navigationTitle("编辑 2FA 账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        account.issuer = issuer.isEmpty ? "未命名" : issuer
        account.accountName = accountName
        try? context.save()
    }
}

// MARK: - 新增 OTP：扫码
//
// 仅支持通过扫二维码（otpauth://totp/...）添加。理由：
//  1. 手输 Base32 密钥体验差且极易出错；
//  2. 减小明文密钥落在剪贴板 / 输入法记忆里的暴露面。
// 相机不可用时提供「粘贴 otpauth 链接」的兜底入口。
//
struct OTPScanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 扫码解析失败时的顶部提示条
    @State private var errorText: String?
    /// 相机初始化失败（无权限 / 无设备）时的降级文案
    @State private var cameraError: String?
    /// 手动粘贴 otpauth 链接的弹窗
    @State private var showPastePrompt = false
    @State private var pastedURL = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let camErr = cameraError {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.slash")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                        Text(camErr)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                        Button("手动粘贴 otpauth 链接") { showPastePrompt = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    QRCodeScannerView(
                        onDetect: handleScannedString,
                        onError: { cameraError = $0 }
                    )
                    .ignoresSafeArea()
                }

                if let err = errorText {
                    VStack {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(err).font(.system(size: 13))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.78)))
                        .foregroundStyle(.white)
                        .padding(.top, 12)
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("扫描 2FA 二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .tint(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPastePrompt = true
                    } label: {
                        Image(systemName: "link")
                    }
                    .tint(.white)
                    .accessibilityLabel("粘贴 otpauth 链接")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("粘贴 otpauth 链接",
                   isPresented: $showPastePrompt) {
                TextField("otpauth://totp/...", text: $pastedURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("取消", role: .cancel) { pastedURL = "" }
                Button("确定") {
                    let url = pastedURL
                    pastedURL = ""
                    handleScannedString(url)
                }
            } message: {
                Text("从其他设备或密码管理器复制的 otpauth 链接")
            }
        }
    }

    private func handleScannedString(_ raw: String) {
        guard let parsed = OTPAuthURL.parse(raw) else {
            showError("链接不是有效的 otpauth 二维码")
            return
        }
        let key = "otp." + UUID().uuidString
        KeychainManager.save(parsed.secretBase32, for: key)
        let o = OTPAccount(issuer: parsed.issuer,
                           accountName: parsed.accountName,
                           secretKeychainKey: key,
                           period: parsed.period,
                           digits: parsed.digits)
        context.insert(o)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func showError(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) { errorText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) { errorText = nil }
        }
    }
}

