//
//  IconPickerSheet.swift
//  美食图标弹窗：Emoji / 相册 / 拍照 三选一
//

import SwiftUI
import PhotosUI
import UIKit

/// 统一的图标回传协议：emoji 字符 或 已压缩 JPEG 二进制。
enum FoodIcon: Equatable {
    case emoji(String)
    case image(Data)
}

private enum IconTab: Hashable { case emoji, album, camera }

struct IconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: FoodIcon
    let onConfirm: (FoodIcon) -> Void
    let emojiCandidates: [String]

    @State private var current: FoodIcon
    @State private var tab: IconTab = .emoji

    // 相册
    @State private var pickedItem: PhotosPickerItem?
    @State private var albumBusy: Bool = false

    // 拍照
    @State private var showCamera: Bool = false

    /// FoodRecord 等模块的默认 emoji 候选（30 个，覆盖火锅/奶茶/中餐/西餐/日料/咖啡/大排档等）
    static let defaultFoodEmoji: [String] = [
        "🍽️", "🍜", "🍚", "🍛", "🍲", "🍱",
        "🍣", "🍤", "🥟", "🍔", "🍕", "🌮",
        "🥗", "🍖", "🍗", "🥘", "🍢", "🍧",
        "🍰", "🧁", "🍩", "🍪", "🍦", "🍮",
        "☕️", "🍵", "🧋", "🥤", "🍺", "🍷"
    ]

    /// CookRecipe 模块的菜肴专用 emoji 候选（30 个，偏烹饪场景）
    static let cookEmoji: [String] = [
        "🍳", "🥘", "🥗", "🍲", "🍜", "🍚",
        "🍛", "🍢", "🍣", "🍤", "🥟", "🍝",
        "🍞", "🥖", "🧀", "🍗", "🍖", "🥩",
        "🍔", "🍟", "🍕", "🌭", "🌮", "🌯",
        "🥙", "🥚", "🥞", "🧇", "🥓", "🥪"
    ]

    init(initial: FoodIcon,
         onConfirm: @escaping (FoodIcon) -> Void,
         emojiCandidates: [String] = IconPickerSheet.defaultFoodEmoji) {
        self.initial = initial
        self.onConfirm = onConfirm
        self.emojiCandidates = emojiCandidates
        _current = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部 tab
                MiniSegmentedPill(items: [
                    (IconTab.emoji, "Emoji"),
                    (IconTab.album, "相册"),
                    (IconTab.camera, "拍照")
                ], selection: $tab)
                .padding(.vertical, 12)

                // 中部内容
                Group {
                    switch tab {
                    case .emoji:  emojiGrid
                    case .album:  albumPane
                    case .camera: cameraPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)

                // 底部预览 + 保存
                Divider()
                HStack(spacing: 12) {
                    preview
                        .frame(width: 40, height: 40)
                    Spacer()
                    Button("保存") {
                        onConfirm(current)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
            }
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    if let d = data { current = .image(d) }
                    showCamera = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private var preview: some View {
        switch current {
        case .emoji(let s):
            Text(s.isEmpty ? "🍽️" : s)
                .font(.system(size: 26))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppColorTheme.bg))
        case .image(let d):
            if let ui = UIImage(data: d) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColorTheme.bg)
                    .frame(width: 40, height: 40)
            }
        }
    }

    // MARK: - Emoji tab

    private var emojiGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
        return ScrollView {
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(emojiCandidates, id: \.self) { e in
                    Button {
                        current = .emoji(e)
                    } label: {
                        Text(e)
                            .font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isCurrentEmoji(e)
                                          ? AppColorTheme.primary.opacity(0.12)
                                          : AppColorTheme.bg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isCurrentEmoji(e) ? AppColorTheme.primary : .clear,
                                            lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func isCurrentEmoji(_ e: String) -> Bool {
        if case .emoji(let s) = current { return s == e }
        return false
    }

    // MARK: - 相册 tab

    private var albumPane: some View {
        VStack(spacing: 16) {
            if case .image(let d) = current, let ui = UIImage(data: d) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Text("重新选择")
                        .font(.system(size: 14, weight: .medium))
                }
            } else {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundStyle(AppColorTheme.primary)
                        Text("从相册选择照片")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColorTheme.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
                }
            }
            if albumBusy {
                ProgressView()
            }
            Spacer()
        }
        .padding(.top, 8)
        .onChange(of: pickedItem) { _, newValue in
            guard let item = newValue else { return }
            albumBusy = true
            Task {
                let raw = try? await item.loadTransferable(type: Data.self)
                let compressed = raw.flatMap { ImageProcessor.compress(data: $0) }
                await MainActor.run {
                    if let c = compressed { current = .image(c) }
                    albumBusy = false
                }
            }
        }
    }

    // MARK: - 拍照 tab

    private var cameraPane: some View {
        VStack(spacing: 16) {
            if case .image(let d) = current, let ui = UIImage(data: d) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button("重新拍照") { showCamera = true }
                    .font(.system(size: 14, weight: .medium))
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            } else {
                Button {
                    showCamera = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(AppColorTheme.primary)
                        Text("打开相机拍照")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColorTheme.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppColorTheme.bg))
                }
                .buttonStyle(.plain)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Text("当前设备无相机")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColorTheme.textSub)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - 相机 UIImagePickerController 薄包装

private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data?) -> Void
        init(onCapture: @escaping (Data?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            // 直接把 UIImage 交给 ImageProcessor 走 UIImage 分支（避免二次 Data→UIImage 转码）
            let data = image.flatMap { ImageProcessor.compress(uiImage: $0) }
            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
