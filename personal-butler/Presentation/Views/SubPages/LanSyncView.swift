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

                Section("设备") {
                    HStack {
                        Text("设备 ID")
                        Spacer()
                        Text(AppSyncConfig.deviceID.prefix(8) + "…")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppColorTheme.textSub)
                    }
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
                        Label("上传备份到内网服务器", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(running || host.isEmpty)

                    Button {
                        Task { await doDownload() }
                    } label: {
                        Label("从内网服务器恢复数据", systemImage: "icloud.and.arrow.down")
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
                }
            }
        }
    }

    private func doUpload() async {
        guard await LocalAuthService.authenticate(reason: "上传备份到局域网服务器") else { return }
        running = true; defer { running = false }
        let uc = BackupSyncUseCase(context: context)
        do {
            try await uc.upload()
            env.markSynced()
            message = "上传成功"
        } catch {
            message = "上传失败：\(error.localizedDescription)"
        }
    }

    private func doDownload() async {
        guard await LocalAuthService.authenticate(reason: "从局域网服务器恢复数据") else { return }
        running = true; defer { running = false }
        let uc = BackupSyncUseCase(context: context)
        do {
            let payload = try await uc.download()
            try uc.restore(payload)
            env.markSynced()
            message = "恢复成功"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f.string(from: d)
    }
}
