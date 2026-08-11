import SwiftUI

/// Shared image pager for place heroes and dossier galleries. It keeps the
/// single-image case visually identical, and only adds swipe dots when a richer
/// media payload supplies multiple resolved images.
struct LoreImageCarousel: View {
    let urls: [URL]
    let title: String
    var height: CGFloat = 200
    var cornerRadius: CGFloat = 16
    var background: Color = LoreColor.bone200
    var activeDot: Color = LoreColor.brass700
    var inactiveDot: Color = LoreColor.bone.opacity(0.72)
    @Binding var selection: Int

    var body: some View {
        Group {
            if urls.isEmpty {
                image(url: nil)
            } else if urls.count == 1 {
                image(url: urls[0])
            } else {
                ZStack(alignment: .bottom) {
                    TabView(selection: $selection) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            image(url: url)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    dots
                        .padding(.bottom, 10)
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .loreElevation(.elev1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text(urls.count > 1 ? "Swipe left or right for more photos." : ""))
        .onChange(of: urls) { _, newURLs in
            if selection >= newURLs.count {
                selection = 0
            }
        }
    }

    @ViewBuilder
    private func image(url: URL?) -> some View {
        BlurUpAsyncImage(url: url)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .kenBurns()
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(urls.indices, id: \.self) { index in
                Capsule()
                    .fill(index == selection ? activeDot : inactiveDot)
                    .frame(width: index == selection ? 16 : 6, height: 6)
                    .animation(.easeOut(duration: 0.18), value: selection)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        urls.count > 1 ? "Photo gallery for \(title)" : "Photo of \(title)"
    }

    private var accessibilityValue: String {
        guard urls.count > 1 else { return "" }
        return "Image \(min(selection + 1, urls.count)) of \(urls.count)"
    }
}
