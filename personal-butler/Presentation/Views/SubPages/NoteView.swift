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

    private let tags = ["全部", "灵感", "摘录", "待整理"]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppColorTheme.textSub)
                    TextField("搜索", text: $search).font(.system(size: 14))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppColorTheme.bg))
                .padding(.horizontal, 16).padding(.top, 12)

                HorizontalTagBar(items: tags, selectedIndex: $filterIndex)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { n in
                            row(n)
                            Divider().padding(.leading, 16)
                        }
                    }
                    Spacer(minLength: 80)
                }
            }
            .background(Color.white)

            FABAddButton { showCreate = true }
        }
        .navigationTitle("笔记")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) { CreateNoteSheet() }
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
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(f.string(from: n.updatedAt))
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

struct CreateNoteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var tag = "灵感"

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
            .navigationTitle("新增笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let n = Note(title: title, content: content, tag: tag)
                        context.insert(n)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
