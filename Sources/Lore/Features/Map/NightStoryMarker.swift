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
                // The wisp: a faint halo that breathes. Static under Reduce
                // Motion — the glow stays, the pulse goes.
                Circle()
                    .fill(LoreColor.amber.opacity(0.28))
                    .frame(width: 40, height: 40)
                    .blur(radius: 6)
                    .scaleEffect(breathing && !reduceMotion ? 1.25 : 1.0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                        value: breathing
                    )
                Circle()
                    .fill(LoreColor.ink900.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(LoreColor.amber.opacity(0.7), lineWidth: 1))
                Text(story.displayEmoji)
                    .font(.system(size: 15))
            }
        }
        .buttonStyle(.plain)
        .onAppear { breathing = true }
        .accessibilityLabel(Text("Night story: \(story.title)"))
    }
}
