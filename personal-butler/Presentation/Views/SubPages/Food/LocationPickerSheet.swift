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

    // 反解显示
    @State private var revLabel: String = "拖动地图选择位置"
    @State private var revSubLabel: String = ""
    @State private var revTask: Task<Void, Never>?
    @State private var lastRevCoord: CLLocationCoordinate2D?

    // 最终回传给业务的字段（与显示分离，避免被后续 camera 变化覆盖）
    @State private var pickedPlaceName: String?    // 上次 POI 搜索或 initial 带入的正式店名
    @State private var pickedAddress: String?      // 反解或 POI 附带的最新地址
    @State private var hasInteracted: Bool         // 是否至少做过一次有效交互（选 POI 或位移 > 50m）
    @State private var initialCoord: CLLocationCoordinate2D  // 初始中心，用于判断"是否位移"
    @State private var suppressReverseGeocode: Bool = false  // POI 选中后抑制紧跟着的相机变化触发的反解

    init(initial: SelectedLocation?,
         onConfirm: @escaping (SelectedLocation) -> Void) {
        self.initial = initial
        self.onConfirm = onConfirm
        // 未传初始位置时用一个默认区域（北京中心）展示地图；用户必须至少交互一次（选 POI 或明显位移）才能保存
        let coord = initial.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        _centerCoord = State(initialValue: coord)
        _initialCoord = State(initialValue: coord)
        _camera = State(initialValue: .region(
            MKCoordinateRegion(center: coord,
                               span: MKCoordinateSpan(latitudeDelta: 0.05,
                                                     longitudeDelta: 0.05))
        ))
        _pickedPlaceName = State(initialValue: initial?.placeName)
        _pickedAddress = State(initialValue: initial?.address)
        // 编辑已录入位置的场景视为已交互；全新录入必须至少交互一次
        _hasInteracted = State(initialValue: initial != nil)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $camera)
                    .mapControls { MapCompass() }
                    .onMapCameraChange { ctx in
                        centerCoord = ctx.camera.centerCoordinate
                        currentRegion = ctx.region

                        // POI 选中后紧跟的相机变化：跳过反解，避免覆盖 pickedAddress
                        if suppressReverseGeocode {
                            suppressReverseGeocode = false
                            return
                        }

                        // 距离初始中心 > 50m 视为"真正的位移"：标记已交互并清空 POI 名
                        let a = CLLocation(latitude: initialCoord.latitude, longitude: initialCoord.longitude)
                        let b = CLLocation(latitude: centerCoord.latitude, longitude: centerCoord.longitude)
                        if a.distance(from: b) > 50 {
                            hasInteracted = true
                            // 拖走了 POI 名不再有效；pickedAddress 会由随后的反解回填
                            pickedPlaceName = nil
                        }

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
                            placeName: pickedPlaceName,
                            address: pickedAddress,
                            latitude: centerCoord.latitude,
                            longitude: centerCoord.longitude
                        ))
                        dismiss()
                    }
                    .disabled(!hasInteracted)
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
        // 关键：POI 已带正式名与地址，直接落库到"picked*"字段
        pickedPlaceName = picked.placeName
        pickedAddress = picked.address
        hasInteracted = true
        // 抑制随后由 camera 变化触发的一次反解，避免覆盖 pickedAddress
        suppressReverseGeocode = true

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
                // 只有当前没有 POI 名时（即拖动场景），才用反解结果回填 pickedAddress；
                // 若已有 POI 名（applyPicked 已设 pickedAddress），保持不覆盖
                if self.pickedPlaceName == nil {
                    self.pickedAddress = addr.isEmpty ? nil : addr
                }
            }
        }
    }
}
