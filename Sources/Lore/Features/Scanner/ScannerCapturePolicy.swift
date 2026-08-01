import Foundation

enum ScannerCapturePolicy {
    static func canCaptureMoment(
        preciseMode: Bool,
        isTransitioningToPreciseMode: Bool,
        permissionDenied: Bool,
        needsPreciseLocation: Bool,
        localContextBlocksScanning: Bool,
        isLoadingContent: Bool,
        hasLockedPlace: Bool
    ) -> Bool {
        !preciseMode
            && !isTransitioningToPreciseMode
            && !permissionDenied
            && !needsPreciseLocation
            && !localContextBlocksScanning
            && !isLoadingContent
            && hasLockedPlace
    }
}
