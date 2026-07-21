//
//  LocalBackupSheet.swift
//  本地备份 / 恢复
//

import SwiftUI
import SwiftData

struct LocalBackupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("本地备份") {
                    Button {
                        Task { await doExport() }
                    } label: {
                        Label("导出备份到文件", systemImage: "square.and.arrow.up")
                    }
                }
                Section("说明") {
                    Text("备份文件以 JSON 结构导出，包含所有 App 数据与密码/2FA 密钥（明文，仅本地保存）。可通过「文件」App 分享或存至 iCloud Drive。")
                        .font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                }
                if let m = message {
                    Section { Text(m).font(.system(size: 13)) }
                }
                if let url = exportURL {
                    Section {
                        ShareLink(item: url) {
                            Label("分享 / 保存到文件 App", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                }
            }
            .navigationTitle("数据备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func doExport() async {
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
            exportURL = url
            message = "已导出：\(filename)"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }
}
