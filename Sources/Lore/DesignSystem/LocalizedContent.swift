import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Renders a block of English source content in the reader's chosen language,
/// translated ON DEVICE (Apple's Translation framework, iOS 18+). Free, private,
/// works offline once the language pack is present, and clearly labelled as a
/// translation — the honest way to take Lore's stories global without a
/// pre-translation pipeline or a server-side MT bill.
///
/// The content closure receives the resolved text plus a `translated` flag so
/// callers can badge it. On iOS 17, or English, or if translation is
/// unavailable, the original English is passed through unchanged — never a
/// half-translated or fabricated string.
struct LocalizedContent<Content: View>: View {
    let source: String
    @ViewBuilder var content: (_ text: String, _ translated: Bool) -> Content

    // Reading L10n.shared.language here registers the @Observable dependency, so
    // changing the language in Settings re-renders (and re-translates) live.
    var body: some View {
        let language = L10n.shared.language
        #if canImport(Translation)
        if #available(iOS 18.0, *), language != .en, !source.isEmpty {
            TranslatingBlock(source: source, target: language.rawValue, content: content)
        } else {
            content(source, false)
        }
        #else
        content(source, false)
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct TranslatingBlock<Content: View>: View {
    let source: String
    let target: String
    @ViewBuilder var content: (_ text: String, _ translated: Bool) -> Content

    @State private var translated: String?
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        content(translated ?? source, translated != nil)
            .translationTask(configuration) { session in
                if let response = try? await session.translate(source) {
                    translated = response.targetText
                }
            }
            // Rebuild the config when the target language changes; downloading a
            // language pack the first time is handled by the system.
            .task(id: target) {
                translated = nil
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: target)
                )
            }
    }
}
#endif

/// A small, honest "translated on device" badge to sit under machine-translated
/// content, so the reader always knows the prose was auto-translated (and the
/// original is English).
struct TranslatedBadge: View {
    var body: some View {
        Label(L10n.t("content.translated"), systemImage: "character.bubble")
            .font(LoreType.caption)
            .foregroundStyle(LoreColor.ink600)
    }
}
