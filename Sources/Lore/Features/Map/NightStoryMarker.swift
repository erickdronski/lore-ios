import SwiftUI

/// A ghost-story marker on the night map: a softly pulsing amber wisp holding
/// the story's emoji (👻 by default). Deliberately quieter than place pins —
/// the night layer should feel discovered, not advertised. Tapping opens the
/// story sheet.
struct NightStoryMarker: View {
    let story: Story
    var onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Button(action: { Haptics.play(.chipTap); onTap() }) {
            ZStack {
                // The wisp GLOW: a broad amber bloom that breathes, so the
                // ghost reads clearly against the dark night map (it used to be
                // a dark disc on a dark map — invisible). Static under Reduce
                // Motion: the glow stays, the pulse goes.
                Circle()
                    .fill(LoreColor.amber.opacity(0.55))
                    .frame(width: 44, height: 44)
                    .blur(radius: 10)
                    .scaleEffect(breathing && !reduceMotion ? 1.3 : 1.0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                        value: breathing
                    )
                // The orb: amber-lit so it pops on dark, ringed brighter still.
                Circle()
                    .fill(LoreColor.amber)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(LoreColor.bone.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: LoreColor.amber.opacity(0.8), radius: 5)
                Text(story.displayEmoji)
                    .font(.system(size: 15))
            }
        }
        .buttonStyle(.plain)
        .onAppear { breathing = true }
        .accessibilityLabel(Text("Night story: \(story.title)"))
    }
}
