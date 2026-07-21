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

    @State private var tab: Tab = .password
    @State private var filterIndex: Int = 0
    @State private var authed = false
    @State private var showCreatePwd = false
    @State private var showCreateOTP = false

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
        .sheet(isPresented: $showCreatePwd) { CreatePasswordSheet() }
        .sheet(isPresented: $showCreateOTP) { CreateOTPSheet() }
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
            SegmentedPill(items: [(Tab.password, "密码"), (Tab.otp, "2FA 验证器")],
                          selection: $tab)
                .padding(.horizontal, 16).padding(.top, 12)

            if tab == .password {
                HorizontalTagBar(items: categories.map { $0.0 }, selectedIndex: $filterIndex)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredPwds, id: \.id) { p in
                            PasswordCardView(account: p)
                        }
                    }
                    .padding(.horizontal, 16)
                    Spacer(minLength: 80)
                }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(otps, id: \.id) { o in
                            OTPCodeCell(account: o)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12)
                    Spacer(minLength: 80)
                }
            }
        }
        .background(Color.white)
    }

    private var filteredPwds: [PasswordAccount] {
        guard let cat = categories[filterIndex].1 else { return accounts }
        return accounts.filter { $0.category == cat }
    }
}

// MARK: - 密码卡片
private struct PasswordCardView: View {
    let account: PasswordAccount
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
                    ("doc.on.doc", { UIPasteboard.general.string = account.account })
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
                            UIPasteboard.general.string = plain
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
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
        .onTapGesture {
            UIPasteboard.general.string = code
        }
        .onAppear { refresh() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        guard let secret = KeychainManager.load(account.secretKeychainKey) else { return }
        code = OTPGenerator.totp(secretBase32: secret, period: account.period, digits: account.digits)
        remaining = OTPGenerator.remainingSeconds(period: account.period)
    }
}

// MARK: - 新增密码
struct CreatePasswordSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var platform = ""
    @State private var account = ""
    @State private var password = ""
    @State private var category: PasswordCategory = .social

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("平台名（如 微信）", text: $platform)
                    TextField("账号", text: $account)
                    SecureField("密码", text: $password)
                }
                Section {
                    Picker("分类", selection: $category) {
                        ForEach(PasswordCategory.allCases, id: \.self) { c in
                            Text(c.label).tag(c)
                        }
                    }
                }
            }
            .navigationTitle("新增密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let key = "pwd." + UUID().uuidString
                        KeychainManager.save(password, for: key)
                        let p = PasswordAccount(platform: platform.isEmpty ? "未命名" : platform,
                                                account: account, typeText: category.label,
                                                category: category, passwordKeychainKey: key)
                        context.insert(p)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 新增 OTP
struct CreateOTPSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var issuer = ""
    @State private var accountName = ""
    @State private var secret = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务商（GitHub / Google...）", text: $issuer)
                    TextField("账号名", text: $accountName)
                    TextField("Base32 密钥", text: $secret)
                        .textInputAutocapitalization(.characters)
                }
                Section {
                    Text("密钥格式：Base32（A-Z 2-7）。仅存储于 iOS Keychain。")
                        .font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                }
            }
            .navigationTitle("新增 2FA 账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let key = "otp." + UUID().uuidString
                        KeychainManager.save(secret, for: key)
                        let o = OTPAccount(issuer: issuer.isEmpty ? "未命名" : issuer,
                                           accountName: accountName,
                                           secretKeychainKey: key)
                        context.insert(o)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
