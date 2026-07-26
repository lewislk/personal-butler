//
//  PrepTaskSheet.swift
//  准备食材任务详情：逐项勾选食材购买进度
//

import SwiftUI
import SwiftData

struct PrepTaskSheet: View {
    let todo: TodoItem
    @Environment(\.modelContext) private var context

    private var expected: [String] { todo.expectedIngredients }
    private var checked: Set<String> { Set(todo.checkedIngredients) }

    var body: some View {
        NavigationStack {
            List {
                Section("食材清单") {
                    if expected.isEmpty {
                        Text("暂无食材").foregroundStyle(.secondary)
                    } else {
                        ForEach(expected, id: \.self) { name in
                            Button {
                                toggle(name)
                            } label: {
                                HStack {
                                    Image(systemName: checked.contains(name) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(checked.contains(name) ? AppColorTheme.primary : .secondary)
                                    Text(name)
                                        .foregroundStyle(checked.contains(name) ? .secondary : AppColorTheme.text)
                                        .strikethrough(checked.contains(name), color: .secondary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Button("全部已购买") {
                        todo.checkedIngredientsRaw = expected.joined(separator: ",")
                        todo.isDone = true
                        try? context.save()
                    }
                    .disabled(expected.isEmpty)
                }
            }
            .navigationTitle(todo.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func toggle(_ name: String) {
        var set = checked
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
        todo.checkedIngredientsRaw = set.sorted().joined(separator: ",")
        todo.isDone = set.count == expected.count && !expected.isEmpty
        try? context.save()
    }
}
