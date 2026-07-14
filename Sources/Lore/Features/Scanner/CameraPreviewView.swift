import AVFoundation
import CoreMedia
import ImageIO
import QuartzCore
import SwiftUI
import UIKit

/// Owns the single `AVCaptureSession` behind the scanner viewfinder.
///
/// The coarse scanner is pose math over the camera feed; no frames leave the
/// device. One deliberate exception reads the feed on-device only: the QR
/// marker rung (docs/05 §5 ladder, rung 0). A Lore marker at a known spot is
/// centimeter-grade ground truth, so scanning one earns an instant, honest
/// Tier-A resolve where GPS never could (indoors, urban canyons, plaques).
/// The AR pipeline (ARKit + GARSession) replaces this session wholesale at P1
/// (docs/05 §2.2 step 1).
final class ScannerCameraService: NSObject, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.erickdronski.lore.camera-session")
    private var configured = false

    /// Live-frame output for on-device Vision recognition (docs/05 §5 ladder:
    /// an honest "what does the camera see" read that fuses with the geospatial
    /// pointer). Frames NEVER leave the device — they go straight to Apple
    /// Vision on-device, same privacy promise as the QR rung.
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.erickdronski.lore.camera-video", qos: .userInitiated)
    /// Called on the video queue (background) with each throttled frame's pixel
    /// buffer + orientation. The receiver runs Vision off-main and publishes to
    /// main itself; this closure must never touch UI directly.
    var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation) -> Void)?
    /// Cap frame forwarding to ~3 Hz so we don't enqueue 30 buffers a second the
    /// recognizer will just drop.
    private var lastFrameAt: TimeInterval = 0
    private static let frameInterval: TimeInterval = 0.3
    /// Whether the session is *meant* to be running, so an interruption/runtime
    /// recovery never fights a deliberate stop (background, tab switch).
    private var wantsRunning = false
    /// Called (main queue) when camera permission is denied or restricted, so
    /// the UI can show a first-class "enable in Settings" card instead of a
    /// permanently black viewfinder.
    var onPermissionDenied: (() -> Void)?
    /// Still-photo output for the "AR postcard" capture (the un-fakeable hero
    /// image: the real facade + the Lore pin, composited in `ARCaptureSheet`).
    private let photoOutput = AVCapturePhotoOutput()
    /// Retains the in-flight capture delegate until the photo comes back.
    private var captureDelegate: PhotoCaptureDelegate?

    /// QR metadata output for the marker rung. Payloads accepted:
    /// `https://getlore.app/p/<slug>`, `lore://p/<slug>`, `lore:<slug>`.
    private let markerOutput = AVCaptureMetadataOutput()
    /// Called on the main queue with the decoded place slug.
    var onMarkerSlug: ((String) -> Void)?
    private var lastMarkerPayload: String?
    private var lastMarkerAt: TimeInterval = 0

    /// Requests camera permission if needed, then configures + starts the
    /// session off the main thread. Surfaces a denial via `onPermissionDenied`
    /// so the scanner shows a Settings path instead of dead-ending on black.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.startSession()
                } else {
                    DispatchQueue.main.async { self.onPermissionDenied?() }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in self?.onPermissionDenied?() }
        @unknown default:
            break
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = true
            self.configureIfNeeded()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = false
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 1920×1440-class is plenty, no 4K, HDR off (battery, docs/05 §7).
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

        // The still-photo output for AR postcard capture. Preview keeps working
        // exactly as before; this just lets the user freeze a shareable frame.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // The QR marker rung: metadata detection is hardware-cheap and stays
        // on-device. Only `.qr` is scanned, and only Lore payloads act.
        if session.canAddOutput(markerOutput) {
            session.addOutput(markerOutput)
            markerOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)
            if markerOutput.availableMetadataObjectTypes.contains(.qr) {
                markerOutput.metadataObjectTypes = [.qr]
            }
        }

        // Live frames for on-device Vision recognition. BGRA, late frames
        // discarded (we only need the newest), delivered on a dedicated queue.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        }

        // An AVCaptureSession does NOT auto-resume after a runtime error or the
        // end of an interruption (a phone call, another app grabbing the camera),
        // so without this the preview stays permanently black after one.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSessionRecovery),
            name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSessionRecovery),
            name: .AVCaptureSessionInterruptionEnded, object: session)
        configured = true
    }

    /// Re-start the session after a runtime error / interruption, but only if we
    /// still want it running (never fight a deliberate stop).
    @objc private func handleSessionRecovery() {
        sessionQueue.async { [weak self] in
            guard let self, self.wantsRunning, self.configured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: AVCaptureMetadataOutputObjectsDelegate (marker rung)

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
            code.type == .qr,
            let payload = code.stringValue,
            let slug = Self.markerSlug(from: payload)
        else { return }

        // Debounce: the camera re-reads a visible code every frame.
        let now = Date().timeIntervalSince1970
        if payload == lastMarkerPayload, now - lastMarkerAt < 5 { return }
        lastMarkerPayload = payload
        lastMarkerAt = now

        DispatchQueue.main.async { [weak self] in
            self?.onMarkerSlug?(slug)
        }
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate (Vision frames)

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Throttle on the video queue so we forward ~3 frames/sec, not 30.
        let now = CACurrentMediaTime()
        guard now - lastFrameAt >= Self.frameInterval else { return }
        guard let onFrame,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameAt = now
        // Back camera in portrait delivers a landscape-native buffer; `.right`
        // presents it upright to Vision without rotating pixels.
        onFrame(pixelBuffer, .right)
    }

    /// Parse a Lore marker payload into a place slug; nil for foreign QR codes
    /// (which the scanner deliberately ignores, this is not a QR reader app).
    static func markerSlug(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://getlore.app/p/", "http://getlore.app/p/", "lore://p/", "lore:"] {
            if trimmed.lowercased().hasPrefix(prefix) {
                let slug = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return slug.isEmpty ? nil : slug.lowercased()
            }
        }
        return nil
    }

    /// Freeze the current viewfinder frame as EXIF-oriented JPEG `Data`, for the
    /// shareable AR postcard. Returns `Data` (Sendable) rather than a UIImage so
    /// nothing non-Sendable crosses the capture queue into the caller's actor;
    /// the caller builds the `UIImage`. Nil if the session isn't running or the
    /// capture fails; the caller degrades gracefully (no postcard, no crash).
    func capturePhotoData() async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning,
                      self.session.outputs.contains(self.photoOutput) else {
                    cont.resume(returning: nil)
                    return
                }
                let settings = AVCapturePhotoSettings()
                let delegate = PhotoCaptureDelegate { [weak self] data in
                    self?.captureDelegate = nil
                    cont.resume(returning: data)
                }
                self.captureDelegate = delegate
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
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

/// One-shot `AVCapturePhotoOutput` delegate that resolves a single capture into
/// an EXIF-oriented `UIImage`. Retained by `ScannerCameraService` for the life
/// of the capture, then released.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}
