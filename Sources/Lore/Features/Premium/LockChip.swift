import SwiftUI

/// The `lock-plus` premium marker (brand/ELEVATION.md §6): a small brass-sheen
/// pill reading **Lore+**, used to label an affordance that lives behind the
/// membership. It's the app's one consistent "this is premium" glyph — a tour
/// row, an audio button, an offline-pack toggle all wear the same chip so the
/// gate is *learnable*.
///
/// It's presentation-only (no tap target of its own); the surrounding control
/// owns the tap and typically presents `PaywallView`. Sized for placement in a
/// row's trailing edge or over a card corner.
struct LockChip: View {
    /// Optional short label; defaults to "Lore+". Pass e.g. "Trial" or "Audio"
    /// for context-specific chips, though the plain plus mark is the default.
    var label: String = "Lore+"
    /// Whether to draw the little lock glyph before the label. On for a locked
    /// affordance; off for a neutral "this is a plus feature" badge.
    var showsLock: Bool = true
    /// Compact removes the label and shows just the lock glyph in a brass disc
    /// (for tight corners, e.g. over a thumbnail).
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LoreColor.ink)
                    .frame(width: 22, height: 22)
                    .background(BrassSheenSurface(shape: Circle(), sweepOnAppear: false))
            } else {
                HStack(spacing: 4) {
                    if showsLock {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(label)
                        .font(LoreType.label)
                        .tracking(0.6)
                }
                .foregroundStyle(LoreColor.ink)  // Ink text on bright brass ≈ AA
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    BrassSheenSurface(shape: Capsule(), sweepOnAppear: false)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsLock ? "\(label), premium feature" : label)
    }
}

/// A full-width "Unlock with Lore+" call-to-action button — the primary way a
/// gated surface invites the upgrade. Brass-sheen fill with the one-shot sweep,
/// Ink label, docent copy. Fires `.chipTap` and runs `action` (present the
/// paywall).
struct UnlockButton: View {
    /// The line under the title — a specific, warm reason this is worth it.
    /// Docent voice only (brand/ELEVATION.md §1): name the value, don't sell.
    var title: String = "Unlock with Lore+"
    var subtitle: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.chipTap)
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LoreType.button)
                    if let subtitle {
                        Text(subtitle)
                            .font(LoreType.caption)
                            .opacity(0.85)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(LoreColor.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                BrassSheenSurface(shape: RoundedRectangle(cornerRadius: 14))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "Opens the Lore+ upgrade screen")
    }
}
