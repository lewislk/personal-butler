//
//  AllAppView.swift
//  Tab2 · 全部应用（拖拽排序）
//

import SwiftUI
import SwiftData

struct AllAppView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \AppModule.order) private var modules: [AppModule]
    @State private var editing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(AppColorTheme.bg)
    }

    private var header: some View {
        HStack {
            Text("全部应用").font(.system(size: 20, weight: .bold))
            Spacer()
            Button {
                withAnimation { editing.toggle() }
            } label: {
                Text(editing ? "完成" : "排序")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(editing ? AppColorTheme.danger : AppColorTheme.primary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(AppColorTheme.bg)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                hint
                sectionTitle("主页展示 · 前 6 项")
                appList
                Spacer(minLength: 20)
            }
        }
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(AppColorTheme.primary)
                .font(.system(size: 14, weight: .regular))
            Text("长按拖拽应用，调整首页展示顺序。前 6 个将展示在主页。")
                .font(.system(size: 12))
                .foregroundStyle(AppColorTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xEEF3FD)))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColorTheme.textSub)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
    }

    private var appList: some View {
        VStack(spacing: 0) {
            ForEach(Array(modules.enumerated()), id: \.element.id) { idx, m in
                Group {
                    if idx == 6 {
                        HStack { Rectangle().fill(Color(hex: 0xE2E5EA))
                                    .frame(height: 1).overlay(
                            Text("— 首页折叠 —")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: 0xB0B4BA))
                                .padding(.horizontal, 8).background(Color.white)
                        ) }
                        .padding(.vertical, 8)
                    }
                    AppRow(module: m, order: idx + 1, isTop6: idx < 6, editing: editing)
                        .contentShape(Rectangle())
                        .onDrag { NSItemProvider(object: m.id as NSString) }
                        .onDrop(of: [.text],
                                delegate: AppDropDelegate(target: m, list: modules, context: context))
                    if idx < modules.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xF0F2F5), lineWidth: 1))
        .shadow(color: AppColorTheme.cardShadow, radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
}

private struct AppRow: View {
    let module: AppModule
    let order: Int
    let isTop6: Bool
    let editing: Bool
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Button {
            router.open(module.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0xEEF3FD))
                        .frame(width: 34, height: 34)
                    Image(systemName: module.iconSystemName)
                        .font(.system(size: 16))
                        .foregroundStyle(AppColorTheme.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(module.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColorTheme.text)
                        if module.comingSoon {
                            Text("二期")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color(hex: 0xF0F2F5)))
                                .foregroundStyle(AppColorTheme.textSub)
                        }
                    }
                    Text(module.tag)
                        .font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                }
                Spacer()
                ZStack {
                    Circle().fill(isTop6 ? Color(hex: 0xEEF3FD) : AppColorTheme.bg)
                        .frame(width: 22, height: 22)
                    Text("\(order)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isTop6 ? AppColorTheme.primary : AppColorTheme.textSub)
                }
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Color(hex: 0xB0B4BA))
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AppDropDelegate: DropDelegate {
    let target: AppModule
    let list: [AppModule]
    let context: ModelContext

    func performDrop(info: DropInfo) -> Bool {
        info.itemProviders(for: [.text]).first?.loadObject(ofClass: NSString.self) { obj, _ in
            guard let str = obj as? String else { return }
            DispatchQueue.main.async {
                guard let fromIdx = list.firstIndex(where: { $0.id == str }),
                      let toIdx = list.firstIndex(where: { $0.id == target.id }),
                      fromIdx != toIdx else { return }
                var arr = list
                let item = arr.remove(at: fromIdx)
                arr.insert(item, at: toIdx)
                for (i, m) in arr.enumerated() { m.order = i }
                try? context.save()
            }
        }
        return true
    }
}
