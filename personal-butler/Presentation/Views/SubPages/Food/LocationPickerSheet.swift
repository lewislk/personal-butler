//
//  LocationPickerSheet.swift
//  美食记录 · 地图选点（方案 B）
//
//  中心大头针固定屏幕正中；拖地图 → 松手后反解地址；顶部搜索可快速跳转区域。
//

import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: SelectedLocation?
    let onConfirm: (SelectedLocation) -> Void

    // 地图相机（用 position + region 双读；region 用于 MKLocalSearch，coord 用于反解）
    @State private var camera: MapCameraPosition
    @State private var centerCoord: CLLocationCoordinate2D
    @State private var currentRegion: MKCoordinateRegion?

    // 搜索
    @State private var query: String = ""
    @State private var showResults: Bool = false

    // 反解
    @State private var revLabel: String = "拖动地图选择位置"
    @State private var revSubLabel: String = ""
    @State private var revTask: Task<Void, Never>?
    @State private var lastRevCoord: CLLocationCoordinate2D?

    init(initial: SelectedLocation?,
         onConfirm: @escaping (SelectedLocation) -> Void) {
        self.initial = initial
        self.onConfirm = onConfirm
        // 有传入位置就用它；否则用一个默认区域（北京市中心，跨度 10km）
        let coord = initial.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        _centerCoord = State(initialValue: coord)
        _camera = State(initialValue: .region(
            MKCoordinateRegion(center: coord,
                               span: MKCoordinateSpan(latitudeDelta: 0.05,
                                                     longitudeDelta: 0.05))
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $camera)
                    .mapControls { MapCompass() }
                    .onMapCameraChange { ctx in
                        centerCoord = ctx.camera.centerCoordinate
                        currentRegion = ctx.region
                        scheduleReverseGeocode(ctx.camera.centerCoordinate)
                    }
                    .ignoresSafeArea(edges: .bottom)

                // 屏幕中心固定大头针（不随地图移动）
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 32))
                    .foregroundStyle(AppColorTheme.primary)
                    .shadow(radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    searchBar
                    if showResults {
                        POISearchResults(query: query, region: currentRegion) { picked in
                            applyPicked(picked)
                            showResults = false
                            query = ""
                        }
                        .padding(.horizontal, 12)
                        .background(Color.white)
                    }
                    Spacer()
                    bottomCard
                }
            }
            .navigationTitle("地图选点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onConfirm(SelectedLocation(
                            placeName: initial?.placeName,     // 拖点没有 POI 名，保留原始名（若从已选处进入）
                            address: revLabel == "拖动地图选择位置" ? nil : revLabel,
                            latitude: centerCoord.latitude,
                            longitude: centerCoord.longitude
                        ))
                        dismiss()
                    }
                }
            }
            .onAppear {
                scheduleReverseGeocode(centerCoord)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColorTheme.textSub)
            TextField("搜索地点", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onChange(of: query) { _, v in
                    showResults = !v.trimmingCharacters(in: .whitespaces).isEmpty
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    showResults = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColorTheme.textSub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundStyle(AppColorTheme.primary)
                Text(revLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColorTheme.text)
                    .lineLimit(1)
            }
            if !revSubLabel.isEmpty {
                Text(revSubLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColorTheme.textSub)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColorTheme.border).frame(height: 0.5)
        }
    }

    private func applyPicked(_ picked: SelectedLocation) {
        centerCoord = CLLocationCoordinate2D(latitude: picked.latitude,
                                             longitude: picked.longitude)
        camera = .region(MKCoordinateRegion(
            center: centerCoord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        revLabel = picked.placeName ?? picked.address ?? "已选择位置"
        revSubLabel = picked.address ?? ""
    }

    private func scheduleReverseGeocode(_ coord: CLLocationCoordinate2D) {
        // 距上次反解 <20m 时不重复请求，节省 CLGeocoder 配额
        if let last = lastRevCoord {
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if a.distance(from: b) < 20 { return }
        }
        lastRevCoord = coord
        revTask?.cancel()
        revTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)   // 防抖 500ms
            if Task.isCancelled { return }
            let geo = CLGeocoder()
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let placemarks = try? await geo.reverseGeocodeLocation(loc)
            guard let p = placemarks?.first else { return }
            let addr = POISearchResults.formatAddress(p)
            let name = p.name ?? addr
            await MainActor.run {
                self.revLabel = name.isEmpty ? "已选择位置" : name
                self.revSubLabel = addr == name ? "" : addr
            }
        }
    }
}
