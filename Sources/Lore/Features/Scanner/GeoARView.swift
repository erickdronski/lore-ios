import ARKit
import SceneKit
import SwiftUI

/// The precise-mode viewfinder surface: an `ARSCNView` whose only job is
/// rendering the camera background for the session `GeoARSessionController`
/// owns (docs/05 §2.2 step 1, on the pure-Apple rung of the ladder). No
/// SceneKit content is ever added; the world-locked cards are SwiftUI
/// overlays positioned by the controller's `ProjectedPin`s, so the scanner
/// keeps one design system across coarse and precise modes and the render
/// budget stays with the camera (docs/05 §7).
struct GeoARView: UIViewRepresentable {
    let controller: GeoARSessionController

    /// `ARSCNView` that reports its layout so screen-space projection always
    /// uses the live viewport. Rotation is off the table (iPhone portrait
    /// only), but safe-area and layout passes still resize the view.
    final class GeoARSCNView: ARSCNView {
        var onLayout: ((CGSize) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(bounds.size)
        }
    }

    func makeUIView(context: Context) -> GeoARSCNView {
        let view = GeoARSCNView(frame: .zero)
        // Share the controller's session: the view renders its camera feed,
        // the controller keeps the delegate and the anchor lifecycle.
        view.session = controller.session
        // Camera background only: no lighting pipeline, no debug chrome, no
        // scene stats. SwiftUI owns every pixel above the feed.
        view.automaticallyUpdatesLighting = false
        view.showsStatistics = false
        view.onLayout = { [weak controller] size in
            controller?.setViewport(size)
        }
        return view
    }

    func updateUIView(_ uiView: GeoARSCNView, context: Context) {}
}
