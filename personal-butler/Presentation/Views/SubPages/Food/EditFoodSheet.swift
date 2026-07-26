//
//  EditFoodSheet.swift
//  美食记录 · 新增 / 编辑弹窗
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

// MARK: - 新增 / 编辑美食记录弹窗
struct EditFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 传 nil 表示新增，传入实例表示编辑
    let record: FoodRecord?

    @State private var name: String
    @State private var emoji: String
    @State private var rating: Int
    @State private var category: FoodCategory
    @State private var tags: String
    @State private var remark: String
    @State private var placeName: String?
    @State private var address: String?
    @State private var latitude: Double?
    @State private var longitude: Double?

    // 位置 UI 交互
    @State private var poiQuery: String = ""
    @State private var showPOIResults: Bool = false
    @State private var showMapPicker: Bool = false
    @State private var showChangeActions: Bool = false
    @State private var locationErrorText: String?
    @State private var isFetchingCurrent: Bool = false

    init(record: FoodRecord?) {
        self.record = record
        _name = State(initialValue: record?.name ?? "")
        _emoji = State(initialValue: record?.emoji ?? "🍽️")
        _rating = State(initialValue: record?.rating ?? 4)
        _category = State(initialValue: record?.category ?? .chinese)
        _tags = State(initialValue: record?.tagsRaw ?? "")
        _remark = State(initialValue: record?.remark ?? "")
        _placeName = State(initialValue: record?.placeName)
        _address = State(initialValue: record?.address)
        _latitude = State(initialValue: record?.latitude)
        _longitude = State(initialValue: record?.longitude)
    }

    private var isEditing: Bool { record != nil }

    /// 可选 Emoji 面板：覆盖火锅/奶茶/中餐/日料/咖啡等常见品类，末位保留一个通用兜底
    private static let emojiOptions: [String] = [
        "🍽️", "🍜", "🍚", "🍛", "🍲", "🍱",
        "🍣", "🍤", "🥟", "🍔", "🍕", "🌮",
        "🥗", "🍖", "🍗", "🥘", "🍢", "🍧",
        "🍰", "🧁", "🍩", "🍪", "🍦", "🍮",
        "☕️", "🍵", "🧋", "🥤", "🍺", "🍷"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("店名 / 菜品", text: $name)
                }
                Section("图标") {
                    emojiPicker
                }
                Section("评分") {
                    starRating
                }
                Section {
                    Picker("分类", selection: $category) {
                        Text("火锅").tag(FoodCategory.hotpot)
                        Text("奶茶").tag(FoodCategory.milktea)
                        Text("中餐").tag(FoodCategory.chinese)
                        Text("日料").tag(FoodCategory.japanese)
                        Text("咖啡").tag(FoodCategory.coffee)
                    }
                }
                Section("位置") {
                    if hasLocation {
                        // 已录入卡片 + 修改/清除
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(AppColorTheme.primary)
                                Text(placeName ?? address ?? "已选择位置")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColorTheme.text)
                                Spacer()
                                Button("修改") { showChangeActions = true }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 13))
                                Button {
                                    clearLocation()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(AppColorTheme.textSub)
                                }
                                .buttonStyle(.borderless)
                            }
                            if let a = address, a != placeName {
                                Text(a).font(.system(size: 12))
                                    .foregroundStyle(AppColorTheme.textSub)
                            }
                        }

                        Button {
                            openInMaps()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                Text("导航到这里")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(AppColorTheme.primary)
                        }
                    } else {
                        // 未录入：三入口
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(AppColorTheme.textSub)
                            TextField("搜索附近地点", text: $poiQuery)
                                .onChange(of: poiQuery) { _, v in
                                    showPOIResults = !v.trimmingCharacters(in: .whitespaces).isEmpty
                                }
                        }
                        if showPOIResults {
                            POISearchResults(query: poiQuery, region: nil) { picked in
                                apply(picked)
                                showPOIResults = false
                                poiQuery = ""
                            }
                        }
                        Button {
                            useCurrentLocation()
                        } label: {
                            HStack {
                                if isFetchingCurrent {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "location.fill")
                                }
                                Text(isFetchingCurrent ? "获取中…" : "使用当前位置")
                            }
                        }
                        Button {
                            showMapPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "map.fill")
                                Text("地图选点")
                            }
                        }
                        if let err = locationErrorText {
                            HStack {
                                Text(err).font(.system(size: 12))
                                    .foregroundStyle(Color(hex: 0xD9534F))
                                Spacer()
                                if err.contains("权限") {
                                    Button("去设置") { openSystemSettings() }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("标签（逗号分隔）", text: $tags)
                    TextField("备注", text: $remark, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "编辑美食" : "新增美食")
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
            .sheet(isPresented: $showMapPicker) {
                LocationPickerSheet(initial: currentSelected) { picked in
                    apply(picked)
                }
            }
            .confirmationDialog("修改位置", isPresented: $showChangeActions, titleVisibility: .visible) {
                Button("搜索地点") {
                    clearLocation()
                    showPOIResults = false     // 用户再手动展开
                }
                Button("使用当前位置") {
                    useCurrentLocation()
                }
                Button("地图选点") {
                    showMapPicker = true
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var hasLocation: Bool { latitude != nil && longitude != nil }

    private var currentSelected: SelectedLocation? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return SelectedLocation(placeName: placeName, address: address,
                                latitude: lat, longitude: lng)
    }

    private func apply(_ picked: SelectedLocation) {
        placeName = picked.placeName
        address = picked.address
        latitude = picked.latitude
        longitude = picked.longitude
        locationErrorText = nil
    }

    private func clearLocation() {
        placeName = nil; address = nil
        latitude = nil; longitude = nil
        locationErrorText = nil
    }

    private func useCurrentLocation() {
        guard !isFetchingCurrent else { return }
        isFetchingCurrent = true
        locationErrorText = nil
        Task {
            do {
                let coord = try await LocationService.shared.requestOneShot()
                let geo = CLGeocoder()
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let placemarks = try? await geo.reverseGeocodeLocation(loc)
                let p = placemarks?.first
                let picked = SelectedLocation(
                    placeName: p?.name,
                    address: p.map { POISearchResults.formatAddress($0) },
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
                await MainActor.run {
                    apply(picked)
                    isFetchingCurrent = false
                }
            } catch let err as LocationError {
                await MainActor.run {
                    isFetchingCurrent = false
                    switch err {
                    case .denied:      locationErrorText = "位置权限未开启"
                    case .unavailable: locationErrorText = "无法获取当前位置"
                    case .timeout:     locationErrorText = "定位超时，请重试"
                    }
                }
            } catch {
                await MainActor.run {
                    isFetchingCurrent = false
                    locationErrorText = "无法获取当前位置"
                }
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func openInMaps() {
        guard let lat = latitude, let lng = longitude else { return }
        let q = (placeName ?? address ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?q=\(q)&ll=\(lat),\(lng)") else { return }
        UIApplication.shared.open(url)
    }

    private func save() {
        let finalName = name.isEmpty ? "未命名" : name
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let r = record {
            r.name = finalName
            r.emoji = emoji
            r.rating = rating
            r.tagsRaw = tagList.joined(separator: ",")
            r.remark = remark
            r.categoryRaw = category.rawValue
            r.placeName = placeName
            r.address = address
            r.latitude = latitude
            r.longitude = longitude
        } else {
            let f = FoodRecord(name: finalName,
                               emoji: emoji, rating: rating,
                               tags: tagList,
                               remark: remark, category: category,
                               placeName: placeName, address: address,
                               latitude: latitude, longitude: longitude)
            context.insert(f)
        }
        try? context.save()
    }

    // MARK: - Emoji 网格选择
    private var emojiPicker: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Self.emojiOptions, id: \.self) { e in
                Button {
                    emoji = e
                } label: {
                    Text(e)
                        .font(.system(size: 22))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(emoji == e
                                      ? AppColorTheme.primary.opacity(0.12)
                                      : AppColorTheme.bg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(emoji == e ? AppColorTheme.primary : .clear,
                                        lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 5 星评分（点第 N 颗 = N 星；再点当前分值可清 0）
    private var starRating: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    rating = (rating == i) ? 0 : i
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: 26))
                        .foregroundStyle(i <= rating
                                         ? Color(hex: 0xF5A623)
                                         : Color(hex: 0xC7CCD4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(rating > 0 ? "\(rating) 星" : "未评分")
                .font(.system(size: 13))
                .foregroundStyle(AppColorTheme.textSub)
        }
        .padding(.vertical, 4)
    }
}
