import AVFoundation
import SwiftUI
import UIKit

/// Owns the single `AVCaptureSession` behind the scanner viewfinder.
///
/// P0 is preview-only: no frames are read, nothing leaves the device — the
/// coarse scanner is pose math over the camera feed, exactly like the web
/// scanner. The AR pipeline (ARKit + GARSession) replaces this session
/// wholesale at P1 (docs/05 §2.2 step 1).
final class ScannerCameraService {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.lore.lore.camera-session")
    private var configured = false

    /// Requests camera permission if needed, then configures + starts the
    /// session off the main thread.
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            self.sessionQueue.async {
                self.configureIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 1920×1440-class is plenty — no 4K, HDR off (battery, docs/05 §7).
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)
        configured = true
    }

    /// Approximate horizontal field of view of the active camera, degrees.
    /// Drives the bearing → screen-x projection; 60° is a safe wide-angle
    /// default when the device can't report one.
    var horizontalFOVDegrees: Double {
        guard
            let input = session.inputs.first as? AVCaptureDeviceInput
        else { return 60 }
        let fov = Double(input.device.activeFormat.videoFieldOfView)
        return fov > 0 ? fov : 60
    }
}

/// `AVCaptureVideoPreviewLayer` bridged into SwiftUI.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
