//
//  QRCodeScannerView.swift
//  纯 AVFoundation 实现的二维码扫码视图（无第三方依赖）
//
//  用法：QRCodeScannerView { code in ... }
//  组件本身不处理相机权限拒绝的重导流程，调用方负责错误态兜底。
//

import SwiftUI
import AVFoundation
import UIKit

struct QRCodeScannerView: UIViewControllerRepresentable {
    /// 命中一次二维码后回调；回调后 session 自动停下，避免重复触发
    let onDetect: (String) -> Void
    /// 相机初始化失败（无权限 / 无设备）时的回调；调用方决定提示什么
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetect: onDetect)
    }

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.delegate = context.coordinator
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}

    // MARK: - Coordinator：AVCapture metadata 回调 → SwiftUI 闭包
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onDetect: (String) -> Void
        /// 防抖：命中一次后忽略后续帧
        private var didFire = false

        init(onDetect: @escaping (String) -> Void) { self.onDetect = onDetect }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didFire,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr,
                  let str = obj.stringValue else { return }
            didFire = true
            // AVCapture 回调在采集队列，切回主线程给 SwiftUI
            DispatchQueue.main.async { [onDetect] in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDetect(str)
            }
        }
    }

    // MARK: - 相机 ViewController
    final class ScannerVC: UIViewController {
        weak var delegate: Coordinator?
        var onError: ((String) -> Void)?

        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
            addAimingOverlay()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in
                    session.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                session.stopRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                onError?("无法访问相机")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onError?("扫码功能不可用")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview
        }

        /// 中间的取景框 + 半透明遮罩
        private func addAimingOverlay() {
            let overlay = UIView(frame: view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            overlay.isUserInteractionEnabled = false
            view.addSubview(overlay)

            let boxSize: CGFloat = min(view.bounds.width, view.bounds.height) * 0.65
            let box = CAShapeLayer()
            let boxRect = CGRect(x: (view.bounds.width - boxSize) / 2,
                                 y: (view.bounds.height - boxSize) / 2,
                                 width: boxSize, height: boxSize)
            // 挖洞：外框全屏路径，用 evenOdd + 内框路径挖出取景区
            let path = UIBezierPath(rect: view.bounds)
            path.append(UIBezierPath(roundedRect: boxRect, cornerRadius: 16).reversing())
            box.path = path.cgPath
            box.fillRule = .evenOdd
            box.fillColor = UIColor.black.withAlphaComponent(0.35).cgColor
            overlay.backgroundColor = .clear
            overlay.layer.addSublayer(box)

            // 四角描边
            let stroke = CAShapeLayer()
            stroke.path = UIBezierPath(roundedRect: boxRect, cornerRadius: 16).cgPath
            stroke.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
            stroke.lineWidth = 2
            stroke.fillColor = UIColor.clear.cgColor
            overlay.layer.addSublayer(stroke)

            let tip = UILabel()
            tip.text = "将二维码放入框内自动识别"
            tip.textColor = UIColor.white.withAlphaComponent(0.85)
            tip.font = .systemFont(ofSize: 13)
            tip.textAlignment = .center
            tip.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(tip)
            NSLayoutConstraint.activate([
                tip.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                tip.topAnchor.constraint(equalTo: overlay.topAnchor,
                                         constant: (view.bounds.height + boxSize) / 2 + 20)
            ])
        }
    }
}
