//
//  NoteView.swift
//  笔记
//

import SwiftUI
import SwiftData

struct NoteView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.updatedAt, order: .reverse) private var list: [Note]
    @State private var filterIndex = 0
    @State private var showCreate = false
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    @State private var editingNote: Note?
    @State private var pendingDelete: Note?
    /// 当前处于展开态（已左滑露出删除按钮）的笔记 id；同一时刻最多一个
    @State private var openSwipeId: UUID?

    private let tags = ["全部", "灵感", "摘录", "待整理"]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // 搜索框：整块可点击（含 magnifyingglass 图标与边缘留白），点击即聚焦 TextField
                // 固定高度 + fixedSize(vertical) 避免键盘弹起时 SwiftUI 键盘避让把胶囊压扁
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppColorTheme.textSub)
                    TextField("搜索", text: $search)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                    // 清空按钮：仅在有内容时显示；点击清空并保持聚焦，方便继续输入
                    if !search.isEmpty {
                        Button {
                            search = ""
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(AppColorTheme.textSub)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: search.isEmpty)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppColorTheme.bg))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { isSearchFocused = true }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 12)

                HorizontalTagBar(items: tags, selectedIndex: $filterIndex)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { n in
                            row(n)
                            Divider().padding(.leading, 16)
                        }
                        // 尾部占位区域：点击空白也能收键盘 / 收滑动行
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 200)
                            .contentShape(Rectangle())
                    }
                    Spacer(minLength: 80)
                }
                // 滚动时立即收起键盘（iOS 16+）
                .scrollDismissesKeyboard(.immediately)
                // 点击列表空白处：收起已展开的滑动行 + 收起键盘
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if openSwipeId != nil { openSwipeId = nil }
                        if isSearchFocused { isSearchFocused = false }
                    }
                )
                .onChange(of: filterIndex) { _, _ in openSwipeId = nil }
                .onChange(of: search) { _, _ in openSwipeId = nil }
            }
            .background(Color.white)

            FABAddButton { showCreate = true }
        }
        .navigationTitle("笔记")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) { EditNoteSheet(note: nil) }
        .sheet(item: $editingNote) { n in EditNoteSheet(note: n) }
        .alert("删除该笔记？",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let n = pendingDelete {
                    context.delete(n)
                    try? context.save()
                }
                pendingDelete = nil
                openSwipeId = nil
            }
        } message: {
            Text(pendingDelete.map { n in
                let name = n.title.isEmpty ? String(n.content.prefix(12)) : n.title
                return "「\(name)」删除后不可恢复。"
            } ?? "")
        }
    }

    private var filtered: [Note] {
        var arr = list
        if filterIndex > 0 { arr = arr.filter { $0.tag == tags[filterIndex] } }
        if !search.isEmpty {
            arr = arr.filter { $0.content.localizedStandardContains(search) || $0.title.localizedStandardContains(search) }
        }
        return arr
    }

    private func row(_ n: Note) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(
                get: { openSwipeId == n.id },
                set: { openSwipeId = $0 ? n.id : nil }
            ),
            onTap: { editingNote = n },
            onDelete: { pendingDelete = n }
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(NoteView.dateLabel(n.updatedAt))
                        .font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                    Text(n.tag)
                        .font(.system(size: 11))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: 0xEEF3FD)))
                        .foregroundStyle(AppColorTheme.primary)
                    Spacer()
                }
                if !n.title.isEmpty {
                    Text(n.title).font(.system(size: 15, weight: .semibold))
                }
                Text(n.content).font(.system(size: 13))
                    .foregroundStyle(AppColorTheme.text)
                    .lineLimit(3)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let rowDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static func dateLabel(_ d: Date) -> String { rowDateFormatter.string(from: d) }
}

// MARK: - 新增 / 编辑笔记弹窗
struct EditNoteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 传 nil 表示新增，传入实例表示编辑
    let note: Note?

    @State private var title: String
    @State private var content: String
    @State private var tag: String

    init(note: Note?) {
        self.note = note
        _title = State(initialValue: note?.title ?? "")
        _content = State(initialValue: note?.content ?? "")
        _tag = State(initialValue: note?.tag ?? "灵感")
    }

    private var isEditing: Bool { note != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题（可选）", text: $title)
                Picker("标签", selection: $tag) {
                    Text("灵感").tag("灵感")
                    Text("摘录").tag("摘录")
                    Text("待整理").tag("待整理")
                }
                TextField("内容", text: $content, axis: .vertical).lineLimit(6...20)
            }
            .navigationTitle(isEditing ? "编辑笔记" : "新增笔记")
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
        if let n = note {
            n.title = title
            n.content = content
            n.tag = tag
            n.updatedAt = Date()
        } else {
            let n = Note(title: title, content: content, tag: tag)
            context.insert(n)
        }
        try? context.save()
    }
}
