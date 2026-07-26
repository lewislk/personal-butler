//
//  ImageProcessor.swift
//  美食图标图片压缩：JPEG + 长边缩放
//

import UIKit

enum ImageProcessor {
    /// 从原始 Data 压缩：解码为 UIImage → 长边 <= maxLongSide → JPEG 编码。
    /// 无法解码返回 nil。
    static func compress(data raw: Data,
                         maxLongSide: CGFloat = 512,
                         quality: CGFloat = 0.7) -> Data? {
        guard let ui = UIImage(data: raw) else { return nil }
        return compress(uiImage: ui, maxLongSide: maxLongSide, quality: quality)
    }

    /// 从 UIImage 压缩：长边 <= maxLongSide → JPEG 编码。
    static func compress(uiImage: UIImage,
                         maxLongSide: CGFloat = 512,
                         quality: CGFloat = 0.7) -> Data? {
        let img = resize(uiImage, longSide: maxLongSide)
        return img.jpegData(compressionQuality: quality)
    }

    /// 按长边等比缩放；已在长边范围内则原样返回。
    private static func resize(_ img: UIImage, longSide: CGFloat) -> UIImage {
        let w = img.size.width
        let h = img.size.height
        let long = max(w, h)
        guard long > longSide else { return img }
        let scale = longSide / long
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
