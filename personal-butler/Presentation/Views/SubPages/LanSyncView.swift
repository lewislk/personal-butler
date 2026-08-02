//
//  LanSyncView.swift
//  局域网同步页
//

import SwiftUI
import SwiftData

struct LanSyncView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment

    @State private var host: String = AppSyncConfig.host
    @State private var token: String = AppSyncConfig.token
    @State private var running = false
    @State private var message: String?
    /// 上传进度 0..1。nil 表示当前未在上传；非 nil 时按钮区显示进度条。
    /// 进度回调来自 URLSession delegate 队列，需切回主线程更新。
    @State private var uploadProgress: Double?
    /// 下载进度 0..1。语义同 uploadProgress。
    /// 进度来源是服务端响应体（Content-Length），相比 upload 多一种 chunked 退化场景。
    @State private var downloadProgress: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section("局域网服务器") {
                    TextField("IP 地址（如 192.168.1.10）", text: $host)
                        .keyboardType(.URL)
                        .onChange(of: host) { _, v in AppSyncConfig.host = v }
                    Text("端口：\(AppSyncConfig.defaultPort)")
                        .font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                    SecureField("同步密钥", text: $token)
                        .onChange(of: token) { _, v in AppSyncConfig.token = v }
                }

                Section {
                    HStack {
                        Text("上次同步")
                        Spacer()
                        Text(env.lastSyncTime.map { fmt($0) } ?? "未同步")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColorTheme.textSub)
                    }
                }

                Section {
                    Button {
                        Task { await doUpload() }
                    } label: {
                        uploadButtonLabel
                    }
                    .disabled(running || host.isEmpty)

                    Button {
                        Task { await doDownload() }
                    } label: {
                        downloadButtonLabel
                    }
                    .disabled(running || host.isEmpty)
                }

                if let m = message {
                    Section { Text(m).font(.system(size: 13)).foregroundStyle(AppColorTheme.textSub) }
                }
            }
            .navigationTitle("局域网同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                    .disabled(running)
                }
            }
        }
    }

    /// 上传按钮 label：根据 uploadProgress 切换两种形态。
    /// - nil：普通 Label「上传备份到内网服务器」
    /// - 非 nil：竖排 ProgressView + 百分比，让用户直观看到传输进度
    ///   （图片多 / WiFi 弱时尤其重要，避免用户以为卡死又重复点）
    @ViewBuilder
    private var uploadButtonLabel: some View {
        if let p = uploadProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("上传中…", systemImage: "icloud.and.arrow.up")
                    Spacer()
                    Text("\(Int(p * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppColorTheme.textSub)
                }
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .tint(AppColorTheme.primary)
            }
            .padding(.vertical, 2)
        } else {
            Label("上传备份到内网服务器", systemImage: "icloud.and.arrow.up")
        }
    }

    /// 下载按钮 label：根据 downloadProgress 切换。
    /// 与 uploadButtonLabel 结构对称，区别仅在 icon 和文案；进度色块复用同一风格。
    @ViewBuilder
    private var downloadButtonLabel: some View {
        if let p = downloadProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("恢复中…", systemImage: "icloud.and.arrow.down")
                    Spacer()
                    Text("\(Int(p * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppColorTheme.textSub)
                }
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .tint(AppColorTheme.primary)
            }
            .padding(.vertical, 2)
        } else {
            Label("从内网服务器恢复数据", systemImage: "icloud.and.arrow.down")
        }
    }

    private func doUpload() async {
        // 提前 flip running：Face ID 期间也算"忙"，防止用户在生物识别弹窗上再点一次按钮。
        // 服务端有 TryLock 兜底（code=2003），此处是 UI 层第一道防线。
        guard !running else { return }
        running = true; defer { running = false }
        defer { uploadProgress = nil }
        guard await LocalAuthService.authenticate(reason: "上传备份到局域网服务器") else { return }
        let uc = BackupSyncUseCase(context: context)
        do {
            try await uc.upload { fraction in
                // URLSession delegate 在子线程触发，切回主线程更新 @State
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.15)) {
                        uploadProgress = fraction
                    }
                }
            }
            env.markSynced()
            message = "上传成功"
        } catch BackupSyncUseCase.SyncError.inProgress {
            message = "上一次同步还在进行，请稍后重试"
        } catch {
            message = "上传失败：\(error.localizedDescription)"
        }
    }

    private func doDownload() async {
        guard !running else { return }
        running = true; defer { running = false }
        defer { downloadProgress = nil }
        guard await LocalAuthService.authenticate(reason: "从局域网服务器恢复数据") else { return }
        let uc = BackupSyncUseCase(context: context)
        do {
            let payload = try await uc.download { fraction in
                // URLSession delegate 在子线程触发，切回主线程更新 @State
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.15)) {
                        downloadProgress = fraction
                    }
                }
            }
            try uc.restore(payload)
            env.markSynced()
            message = "恢复成功"
        } catch BackupSyncUseCase.SyncError.inProgress {
            message = "上一次同步还在进行，请稍后重试"
        } catch BackupSyncUseCase.SyncError.noBackup {
            message = "服务器上还没有备份，请先上传一次"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f.string(from: d)
    }
}
