import MapKit
import SwiftUI

/// Apple "Look Around" street level imagery for a place, the one great use of
/// the Apple Developer membership on the dossier surface. Doctrine (docs/17,
/// docs/22): MapLibre stays the branded flagship map, and Apple powers the
/// things only Apple has, the AR VPS, turn by turn directions, and this street
/// level view. It is purely additive.
///
/// The section renders ONLY when Apple actually has coverage for this exact
/// spot. Coverage is city and street dependent, so a place with none shows
/// nothing at all rather than an empty frame. Tapping the preview opens the
/// full immersive Look Around experience for free (SwiftUI handles it).
struct LookAroundSection: View {
    let place: Place

    @State private var scene: MKLookAroundScene?
    @State private var checked = false

    var body: some View {
        Group {
            if let scene {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Street level")
                        .font(LoreType.displayM)
                        .foregroundStyle(LoreColor.bone)

                    LookAroundPreview(initialScene: scene, allowsNavigation: true)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(LoreColor.ink700, lineWidth: 1)
                        )
                        .accessibilityLabel(Text("Look around \(place.name) at street level"))
                }
            }
        }
        // Fetch once per place. A missing scene (no coverage) leaves the
        // section empty, never an error, never a spinner.
        .task(id: place.id) {
            guard !checked else { return }
            checked = true
            let request = MKLookAroundSceneRequest(coordinate: place.coordinate)
            scene = try? await request.scene
        }
    }
}
