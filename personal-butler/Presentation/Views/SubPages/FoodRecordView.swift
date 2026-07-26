//
//  FoodRecordView.swift
//  美食记录
//

import SwiftUI
import SwiftData
import UIKit

struct FoodRecordView: View {
    @Environment(\.modelContext) private var context
    // 排序：分值降序优先，同分按更新时间倒序
    @Query(sort: [
        SortDescriptor(\FoodRecord.rating, order: .reverse),
        SortDescriptor(\FoodRecord.updatedAt, order: .reverse)
    ]) private var list: [FoodRecord]
    @State private var filterIndex: Int = 0
    @State private var showCreate = false
    @State private var editingRecord: FoodRecord?
    @State private var pendingDelete: FoodRecord?
    /// 当前处于展开态（已左滑露出删除按钮）的记录 id；同一时刻最多一个
    @State private var openSwipeId: UUID?

    // 列表行位置点击 → 弹导航 App 选择面板
    @State private var showMapsPicker: Bool = false
    @State private var pickerLat: Double = 0
    @State private var pickerLng: Double = 0
    @State private var pickerName: String?

    private let categories: [(String, FoodCategory)] = [
        ("全部", .all),
        ("火锅", .hotpot),
        ("奶茶", .milktea),
        ("中餐", .chinese),
        ("西餐", .western),
        ("大排档", .streetfood),
        ("日料", .japanese),
        ("咖啡", .coffee)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HorizontalTagBar(items: categories.map { $0.0 }, selectedIndex: $filterIndex)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { f in
                            row(f)
                            Divider()
                        }
                        Spacer(minLength: 80)
                    }
                }
                // 点击空白处收起已展开的滑动行
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if openSwipeId != nil {
                            openSwipeId = nil
                        }
                    }
                )
                // 切换分类时也顺手收起
                .onChange(of: filterIndex) { _, _ in openSwipeId = nil }
            }
            .background(Color.white)

            FABAddButton { showCreate = true }
        }
        .navigationTitle("美食记录")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) {
            EditFoodSheet(record: nil)
        }
        .sheet(item: $editingRecord) { r in
            EditFoodSheet(record: r)
        }
        .alert("删除该记录？",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let f = pendingDelete {
                    context.delete(f)
                    try? context.save()
                }
                pendingDelete = nil
                openSwipeId = nil
            }
        } message: {
            Text(pendingDelete.map { "「\($0.name)」删除后不可恢复。" } ?? "")
        }
        .mapsNavigatorPicker(isPresented: $showMapsPicker,
                             latitude: pickerLat,
                             longitude: pickerLng,
                             name: pickerName)
    }

    private var filtered: [FoodRecord] {
        let cat = categories[filterIndex].1
        return cat == .all ? list : list.filter { $0.category == cat }
    }

    private func row(_ f: FoodRecord) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(
                get: { openSwipeId == f.id },
                set: { openSwipeId = $0 ? f.id : nil }
            ),
            onTap: { editingRecord = f },
            onDelete: { pendingDelete = f }
        ) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let data = f.iconImage, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text(f.emoji)
                            .font(.system(size: 32))
                            .frame(width: 90, height: 90)
                            .background(RoundedRectangle(cornerRadius: 10).fill(
                                LinearGradient(colors: gradient(for: f.category),
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            ))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(f.name).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColorTheme.text)
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            let idx = Double(i)
                            let iconName: String =
                                f.rating >= idx + 1.0 ? "star.fill"
                                : f.rating >= idx + 0.5 ? "star.leadinghalf.filled"
                                : "star"
                            Image(systemName: iconName)
                                .font(.system(size: 11))
                                .foregroundStyle(f.rating >= idx + 0.5 ? Color(hex: 0xF5A623) : Color(hex: 0xE2E5EA))
                        }
                    }
                    if !f.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(f.tags, id: \.self) { t in
                                Text(t).font(.system(size: 11))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Capsule().fill(AppColorTheme.bg))
                                    .foregroundStyle(AppColorTheme.textSub)
                            }
                        }
                    }
                    if !f.remark.isEmpty {
                        Text(f.remark).font(.system(size: 12)).foregroundStyle(AppColorTheme.textSub)
                            .lineLimit(2)
                    }
                    if f.hasLocation, let loc = f.displayLocation,
                       let lat = f.latitude, let lng = f.longitude {
                        Button {
                            pickerLat = lat
                            pickerLng = lng
                            pickerName = f.placeName ?? f.address
                            showMapsPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 10))
                                Text(loc)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(AppColorTheme.primary)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(AppColorTheme.textSub)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
    }

    private func gradient(for cat: FoodCategory) -> [Color] {
        switch cat {
        case .japanese: return [Color(hex: 0xBEE1FF), Color(hex: 0x6AA9E9)]
        case .milktea:  return [Color(hex: 0xFFE29A), Color(hex: 0xF0B650)]
        default:        return [Color(hex: 0xFFD7B5), Color(hex: 0xFF8A65)]
        }
    }
}
