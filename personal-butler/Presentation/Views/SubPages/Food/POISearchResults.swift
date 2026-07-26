//
//  POISearchResults.swift
//  POI 搜索结果列表（MKLocalSearch），供 EditFoodSheet 内联使用。
//

import SwiftUI
import MapKit

/// 位置选择结果：跨组件传递（POISearchResults / LocationPickerSheet → EditFoodSheet）
struct SelectedLocation: Equatable {
    let placeName: String?
    let address: String?
    let latitude: Double
    let longitude: Double
}

struct POISearchResults: View {
    /// 当前搜索关键字（外部驱动，本组件不管输入框）
    let query: String
    /// 搜索的 region（当前定位附近 / 兜底默认区域）
    let region: MKCoordinateRegion?
    /// 用户点选后回调，父视图负责收起搜索
    let onPick: (SelectedLocation) -> Void

    @State private var items: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSearching {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("搜索中…")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColorTheme.textSub)
                }
                .padding(.vertical, 8)
            } else if items.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("未找到匹配地点")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
                    .padding(.vertical, 8)
            } else {
                // 包 ScrollView + 限高，结果过多时可滚动，避免撑破父布局
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                            Button {
                                onPick(Self.mapItemToLocation(item))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "未命名地点")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColorTheme.text)
                                        .lineLimit(1)
                                    Text(Self.formatAddress(item.placemark))
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColorTheme.textSub)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().foregroundStyle(Color.black.opacity(0.04))
                        }
                    }
                }
                // 限高：最多约 5 条可见；超过则内部滚动，第一行始终清晰可见
                .frame(maxHeight: 280)
            }
        }
        .onChange(of: query) { _, newValue in
            triggerSearch(newValue)
        }
        .onAppear { triggerSearch(query) }
        .onDisappear { searchTask?.cancel() }
    }

    // 防抖 300ms 触发搜索
    private func triggerSearch(_ raw: String) {
        searchTask?.cancel()
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            items = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = text
            if let region {
                req.region = region
            }
            do {
                let resp = try await MKLocalSearch(request: req).start()
                if Task.isCancelled { return }
                await MainActor.run {
                    self.items = resp.mapItems
                    self.isSearching = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.items = []
                    self.isSearching = false
                }
            }
        }
    }

    static func mapItemToLocation(_ item: MKMapItem) -> SelectedLocation {
        let coord = item.placemark.coordinate
        return SelectedLocation(
            placeName: item.name,
            address: formatAddress(item.placemark),
            latitude: coord.latitude,
            longitude: coord.longitude
        )
    }

    /// 从 CLPlacemark 拼出中文可读地址：administrativeArea + locality + subLocality + thoroughfare + subThoroughfare
    static func formatAddress(_ p: CLPlacemark) -> String {
        [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare, p.subThoroughfare]
            .compactMap { $0 }
            .joined()
    }
}
