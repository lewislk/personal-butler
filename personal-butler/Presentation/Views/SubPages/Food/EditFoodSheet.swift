//
//  EditFoodSheet.swift
//  美食记录 · 新增 / 编辑弹窗
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import UIKit

// MARK: - 新增 / 编辑美食记录弹窗
struct EditFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 传 nil 表示新增，传入实例表示编辑
    let record: FoodRecord?

    @State private var name: String
    @State private var icon: FoodIcon
    @State private var showIconPicker: Bool = false
    @State private var rating: Double
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
        if let data = record?.iconImage {
            _icon = State(initialValue: .image(data))
        } else {
            _icon = State(initialValue: .emoji(record?.emoji ?? "🍽️"))
        }
        _rating = State(initialValue: record?.rating ?? 4.0)
        _category = State(initialValue: record?.category ?? .chinese)
        _tags = State(initialValue: record?.tagsRaw ?? "")
        _remark = State(initialValue: record?.remark ?? "")
        _placeName = State(initialValue: record?.placeName)
        _address = State(initialValue: record?.address)
        _latitude = State(initialValue: record?.latitude)
        _longitude = State(initialValue: record?.longitude)
    }

    private var isEditing: Bool { record != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("店名 / 菜品", text: $name)
                }
                Section("图标") {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            iconPreview
                                .frame(width: 60, height: 60)
                            Text("点击更换")
                                .font(.system(size: 15))
                                .foregroundStyle(AppColorTheme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppColorTheme.textSub)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section("评分") {
                    starRating
                }
                Section {
                    Picker("分类", selection: $category) {
                        Text("火锅").tag(FoodCategory.hotpot)
                        Text("奶茶").tag(FoodCategory.milktea)
                        Text("中餐").tag(FoodCategory.chinese)
                        Text("西餐").tag(FoodCategory.western)
                        Text("大排档").tag(FoodCategory.streetfood)
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
            .sheet(isPresented: $showIconPicker) {
                IconPickerSheet(initial: icon) { picked in
                    icon = picked
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
        MapsNavigator.openInMaps(latitude: lat, longitude: lng, name: placeName ?? address)
    }

    private func save() {
        let finalName = name.isEmpty ? "未命名" : name
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let r = record {
            r.name = finalName
            r.rating = rating
            r.tagsRaw = tagList.joined(separator: ",")
            r.remark = remark
            r.categoryRaw = category.rawValue
            r.placeName = placeName
            r.address = address
            r.latitude = latitude
            r.longitude = longitude
            switch icon {
            case .emoji(let s):
                r.emoji = s.isEmpty ? "🍽️" : s
                r.iconImage = nil
            case .image(let d):
                // 保留原 emoji 作为兜底显示（图片被清后仍有 fallback）
                r.iconImage = d
            }
        } else {
            let effectiveEmoji: String
            let effectiveImage: Data?
            switch icon {
            case .emoji(let s):
                effectiveEmoji = s.isEmpty ? "🍽️" : s
                effectiveImage = nil
            case .image(let d):
                effectiveEmoji = "🍽️"     // 兜底 emoji
                effectiveImage = d
            }
            let f = FoodRecord(name: finalName,
                               emoji: effectiveEmoji, rating: rating,
                               tags: tagList,
                               remark: remark, category: category,
                               placeName: placeName, address: address,
                               latitude: latitude, longitude: longitude,
                               iconImage: effectiveImage)
            context.insert(f)
        }
        try? context.save()
    }

    // MARK: - 图标预览（60×60）
    @ViewBuilder
    private var iconPreview: some View {
        switch icon {
        case .emoji(let s):
            Text(s.isEmpty ? "🍽️" : s)
                .font(.system(size: 36))
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppColorTheme.bg))
        case .image(let d):
            if let ui = UIImage(data: d) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColorTheme.bg)
                    .frame(width: 60, height: 60)
            }
        }
    }

    // MARK: - 半星评分（每颗星拆左右两半 tap 区：左半 = +0.5，右半 = +1.0；再点当前值归零）
    private var starRating: some View {
        HStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { i in
                starCell(index: i)
            }
            Spacer()
            Text(rating > 0 ? String(format: "%.1f 星", rating) : "未评分")
                .font(.system(size: 13))
                .foregroundStyle(AppColorTheme.textSub)
        }
        .padding(.vertical, 4)
    }

    /// 每颗星拆左右两半 tap 区：左半 = +0.5，右半 = +1.0；再点当前值归零
    @ViewBuilder
    private func starCell(index i: Int) -> some View {
        let idx = Double(i)
        let iconName: String =
            rating >= idx + 1.0 ? "star.fill"
            : rating >= idx + 0.5 ? "star.leadinghalf.filled"
            : "star"
        let filled = rating >= idx + 0.5

        ZStack {
            Image(systemName: iconName)
                .font(.system(size: 26))
                .foregroundStyle(filled ? Color(hex: 0xF5A623) : Color(hex: 0xC7CCD4))
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: 20, height: 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let target = idx + 0.5
                        rating = (rating == target) ? 0 : target
                    }
                Color.clear
                    .frame(width: 20, height: 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let target = idx + 1.0
                        rating = (rating == target) ? 0 : target
                    }
            }
        }
        .frame(width: 40, height: 40)
    }
}
