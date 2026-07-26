//
//  MineView.swift
//  Tab3 · 我的
//

import SwiftUI
import SwiftData

struct MineView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var env: AppEnvironment
    @Query private var settings: [AppSetting]

    @State private var showBackupSheet = false
    @State private var showSyncSheet = false
    @State private var cacheSize: String = "2.3 MB"
    @State private var toast: String?
    @State private var showClearDemoConfirm = false

    private var setting: AppSetting? { settings.first }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(AppColorTheme.bg)
        .sheet(isPresented: $showBackupSheet) {
            LocalBackupSheet()
        }
        .sheet(isPresented: $showSyncSheet) {
            LanSyncView()
        }
        .alert("清理Demo数据", isPresented: $showClearDemoConfirm) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) { clearDemoData() }
        } message: {
            Text("将删除首启灌入的所有示例数据（日程 / 纪念日 / 密码 / 美食 / 菜谱 / 笔记 / 2FA），你自添的数据不受影响。此操作不可恢复。")
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t).font(.system(size: 13))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.75)))
                    .foregroundStyle(.white)
                    .padding(.bottom, 32)
                    .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("我的").font(.system(size: 20, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColorTheme.border).frame(height: 0.5)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                privacyCard
                aboutCard
                Spacer(minLength: 20)
            }
        }
    }

    private var privacyCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("隐私安全设置")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColorTheme.primary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            row(icon: "lock", label: "应用锁",
                value: setting?.appLockMethod == "faceID" ? "面容ID" : "已开启") { }
            Divider().padding(.leading, 44)
            // 备份 / 恢复合并为一个入口：LocalBackupSheet 内部同时提供「导出到文件」和
            // 「从文件恢复」两个 Section，用户不会混淆。value 显示上次备份时间。
            row(icon: "externaldrive", label: "数据备份 / 恢复",
                value: setting?.lastBackupAt.map { fmt($0) } ?? "从未") {
                showBackupSheet = true
            }
            Divider().padding(.leading, 44)
            row(icon: "network", label: "局域网同步",
                value: env.lastSyncTime.map { fmt($0) } ?? "未同步") {
                showSyncSheet = true
            }
            Divider().padding(.leading, 44)
            row(icon: "trash", label: "清除缓存", value: cacheSize) {
                cacheSize = "0 KB"
                showToast("已清除")
            }
            Divider().padding(.leading, 44)
            row(icon: "sparkles", label: "清理Demo数据", value: "示例数据") {
                showClearDemoConfirm = true
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xF0F2F5), lineWidth: 1))
        .shadow(color: AppColorTheme.cardShadow, radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16).padding(.top, 16)
    }

    private var aboutCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("关于").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColorTheme.textSub)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            row(icon: "info.circle", label: "版本信息", value: "v1.0.0") { }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xF0F2F5), lineWidth: 1))
        .shadow(color: AppColorTheme.cardShadow, radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16).padding(.top, 16)
    }

    private func row(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColorTheme.textSub)
                    .frame(width: 20)
                Text(label).font(.system(size: 14)).foregroundStyle(AppColorTheme.text)
                Spacer()
                Text(value).font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                Image(systemName: "chevron.right").font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xC4C7CC))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f.string(from: d)
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { toast = nil }
        }
    }

    /// 清理首启灌入的 Demo 数据（isDemo==true 的记录）。
    /// 用户自添数据保留；失败时 toast 提示错误。
    private func clearDemoData() {
        do {
            let count = try SeedData.clearDemoData(in: context)
            showToast(count > 0 ? "已清理 \(count) 条Demo数据" : "没有可清理的Demo数据")
        } catch {
            showToast("清理失败：\(error.localizedDescription)")
        }
    }
}
