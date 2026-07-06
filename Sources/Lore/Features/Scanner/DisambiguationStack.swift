import SwiftUI

/// The disambiguation **stack** (docs/12 §2.1): when several candidates fall
/// inside one bearing cone (a dense skyline, a row of Beaux-Arts façades) the
/// scanner refuses to guess and instead shows one stack chip with a count.
/// Tapping opens a distance-sorted, live-reordering list; the one the user
/// confirms is what snaps to a Tier-A pin and (silently, opt-in) would feed a
/// `verification` at P1, the crowd sharpening the model with every confirmed
/// look. Here we render the honest UI and surface the confirmation callback;
/// the network verification write is the P1 hook (docs/06 crowdsourcing).
///
/// Chrome over live camera: Amber/Ink/Bone only, `material.overlay` so the
/// camera stays legible through it (brand/DESIGN.md §3–4).
struct StackChip: View {
    let cluster: ScannerRanking.Cluster
    /// The user picked a candidate from the opened list → snap it to a pin.
    var onConfirm: (ScannerRanking.Ranked) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            collapsedChip
            if isOpen {
                candidateList
            }
        }
        // The stack expands as a settled panel, `spring.smooth`, no jaunty
        // overshoot on a decision UI (LUXURY-MOTION §2, §7).
        .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: isOpen)
    }

    // MARK: Collapsed, the count chip

    private var collapsedChip: some View {
        Button {
            Haptics.play(.chipTap)
            withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(cluster.lead.place.displayEmoji)
                    .font(.system(size: 13))
                Text(cluster.isStack ? "One of these \(cluster.count)" : cluster.lead.place.name)
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
                    .lineLimit(1)
                if cluster.isStack {
                    Text("\(cluster.count)")
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(LoreColor.amber, in: Capsule())
                }
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LoreColor.amber)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(LoreColor.amber.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(
            cluster.isStack
                ? "\(cluster.count) possible places this way, tap to disambiguate"
                : "\(cluster.lead.place.name), \(cluster.lead.projected.distanceLabel) away"
        ))
    }

    // MARK: Open, distance-sorted rows

    /// The candidate rows, nearest-first (docs/12 §2.1). Rows cascade in with a
    /// 30 ms stagger (brand/DESIGN §6 "Stack open"); the model re-sorts by
    /// distance as the user walks, so the list live-reorders under them.
    private var candidateList: some View {
        VStack(spacing: 4) {
            ForEach(Array(cluster.members.enumerated()), id: \.element.id) { index, member in
                Button {
                    Haptics.play(.scannerLock)
                    onConfirm(member)
                } label: {
                    candidateRow(member)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
                // Rows cascade in with a 30 ms stagger on a settled spring.
                .animation(
                    reduceMotion
                        ? LoreSpring.reducedCrossfade
                        : LoreSpring.smooth.delay(Double(min(index, 6)) * 0.03),
                    value: isOpen
                )
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LoreColor.amber.opacity(0.35), lineWidth: 1)
        )
    }

    private func candidateRow(_ member: ScannerRanking.Ranked) -> some View {
        HStack(spacing: 8) {
            Text(member.place.displayEmoji)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(member.place.name)
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
                    .lineLimit(1)
                Text(member.place.kind.capitalized)
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.bone.opacity(0.7))
            }
            Spacer(minLength: 8)
            Text(member.projected.distanceLabel)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.amber)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 44) // HIG touch target (brand/DESIGN §8)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(
            "\(member.place.name), \(member.place.kind), \(member.projected.distanceLabel) away. Confirm to pin."
        ))
    }
}
