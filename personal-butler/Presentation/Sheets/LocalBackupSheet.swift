//
//  LocalBackupSheet.swift
//  本地备份 / 恢复：导出 JSON 到「文件」App / 从 JSON 恢复
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LocalBackupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var message: String?
    @State private var showImporter = false
    @State private var showRestoreConfirm = false
    /// 用户在 fileImporter 里选中的备份文件；确认后才真正 restore。
    @State private var pendingImportURL: URL?
    @State private var running = false

    var body: some View {
        NavigationStack {
            Form {
                Section("导出到文件") {
                    Button {
                        Task { await doExport() }
                    } label: {
                        Label("生成备份文件", systemImage: "square.and.arrow.up")
                    }
                    .disabled(running)
                }

                // 只有生成完备份文件后才出现的「保存」引导区。
                // 强调"生成 ≠ 已保存"—— 文件目前只在 App 沙盒 tmp/，系统随时可能清；
                // 必须点 ShareLink → 存储到文件 App 才算真正保存到用户可见的位置。
                if let url = exportURL {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("文件已生成，请立即保存", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.orange)
                            Text(url.lastPathComponent)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(AppColorTheme.textSub)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("文件当前仅存在 App 的临时目录，系统可能随时清除。点击下方按钮选择「存储到文件」→ iCloud Drive 或本机 → PersonalButler 文件夹，才会真正落地。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColorTheme.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)

                        ShareLink(item: url) {
                            Label("保存到「文件」App", systemImage: "square.and.arrow.up.on.square.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColorTheme.primary)
                        }
                    }
                }

                Section("从文件恢复") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("选择备份文件恢复", systemImage: "arrow.down.doc")
                    }
                    .disabled(running)
                }

                Section("说明") {
                    Text("备份文件以 JSON 结构导出，包含所有 App 数据与密码/2FA 密钥（明文，仅本地保存）。**导出后必须通过下方「保存到文件 App」把文件转存出去**，否则会随 App 沙盒临时目录被系统回收。恢复会覆盖当前所有数据（AppSetting 除外），操作前请确认。")
                        .font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                }
                if let m = message {
                    Section { Text(m).font(.system(size: 13)) }
                }
            }
            .navigationTitle("数据备份 / 恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingImportURL = url
                    showRestoreConfirm = true
                case .failure(let err):
                    message = "选择文件失败：\(err.localizedDescription)"
                }
            }
            .alert("确认恢复？", isPresented: $showRestoreConfirm, presenting: pendingImportURL) { url in
                Button("取消", role: .cancel) { pendingImportURL = nil }
                Button("确认覆盖", role: .destructive) {
                    Task { await doImport(url: url) }
                }
            } message: { url in
                Text("将用「\(url.lastPathComponent)」覆盖当前全部数据（AppSetting 除外），此操作不可撤销。")
            }
        }
    }

    private func doExport() async {
        guard !running else { return }
        running = true; defer { running = false }
        guard await LocalAuthService.authenticate(reason: "导出备份") else { return }
        let uc = BackupSyncUseCase(context: context)
        do {
            let payload = try uc.buildPayload()
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
            let data = try enc.encode(payload)
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "PersonalButler_\(f.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            // 文件已在 tmp/ 落地，但用户还没保存出去 —— 交互全部由 exportURL Section 引导，
            // 此处不再弹 "已导出" 提示避免"操作已完成"的误导。
            exportURL = url
            message = nil
        } catch {
            exportURL = nil
            message = "生成备份文件失败：\(error.localizedDescription)"
        }
    }

    /// 从「文件」App 选中的 JSON 备份恢复本地数据。
    /// fileImporter 给的是 security-scoped URL，读之前必须 startAccessing，读完 stop。
    private func doImport(url: URL) async {
        guard !running else { return }
        running = true; defer { running = false }
        defer { pendingImportURL = nil }
        guard await LocalAuthService.authenticate(reason: "从备份文件恢复数据") else { return }

        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(SyncPayload.self, from: data)
            let uc = BackupSyncUseCase(context: context)
            try uc.restore(payload)
            message = "恢复成功：\(url.lastPathComponent)"
        } catch let decodeErr as DecodingError {
            // JSON 结构对不上：字段缺失 / 类型不符 / 版本升级导致的破坏性变更
            message = "备份文件格式无效：\(decodeErr.localizedDescription)"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }
}
