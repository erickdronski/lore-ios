import AVFoundation
import Observation

/// Audio-first, hands-free narration for the scanner (docs/12 §3.2): resolving
/// a Tier-A pin can **auto-offer** the ~20-second narrated hook so a walker
/// never has to read while moving. "Keep walking, I'll tell you" is the docent
/// mode, the phone talks and the user looks up at the actual building, the
/// accessibility win *and* the magic moment.
///
/// P0 is on-device `AVSpeechSynthesizer` (TTS now, recorded voice later, docs/02
/// §product). The hook text comes from the place's Layer-1 (CC0/PD, safe to
/// speak without attribution, docs/04 §2.2). Auto-offer etiquette is the open
/// question (docs/12 open Q4): we *offer* on lock and let the user start it —
/// we do not auto-*play*, which would be intrusive on a quiet street or in a
/// museum. The one-tap start is `speak(_:)`.
@Observable
@MainActor
final class NarrationService {
    /// The place currently being offered narration, if any. Drives the
    /// "Keep walking, I'll tell you" affordance in the scanner.
    private(set) var offered: Place?
    /// True while the synthesizer is actively speaking.
    private(set) var isSpeaking = false
    /// The place we last auto-offered, so a re-lock on the same building
    /// doesn't re-nag (docs/12 open Q4 etiquette).
    private var lastOfferedID: String?

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechDelegate()

    init() {
        delegate.owner = self
        synthesizer.delegate = delegate
    }

    /// The ~20-second hook line for a place, docent voice. Prefers the authored
    /// Layer-1 hook; falls back to a persona-flavored orienting line built from
    /// the place's own facts (never invents history, only reads what's there).
    static func hookText(for place: Place, register: String) -> String {
        if let hook = place.layer1?.hook, !hook.isEmpty {
            return hook
        }
        var line = "\(register) \(place.name)."
        if let year = place.layer1?.yearBuilt {
            line += " Built in \(year)."
        }
        if let architect = place.layer1?.architect, !architect.isEmpty {
            line += " Designed by \(architect)."
        }
        return line
    }

    /// Offer narration for a freshly-locked place (docs/12 §3.2 auto-offer, not
    /// auto-play). Idempotent per place: re-locking the same building won't
    /// re-surface the offer once dismissed or played.
    func offer(_ place: Place) {
        guard lastOfferedID != place.id else { return }
        lastOfferedID = place.id
        offered = place
    }

    /// The user tapped "Keep walking, I'll tell you", speak the hook. Sets the
    /// audio session to duck/ mix so it plays over the ambient world without
    /// hijacking other audio harder than it needs to.
    func speak(_ place: Place, register: String) {
        offered = nil
        // Cancel any in-flight hook so a new lock speaks now, not queued behind
        // the old one (AVSpeechSynthesizer enqueues by default).
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        configureSession()
        let utterance = AVSpeechUtterance(string: Self.hookText(for: place, register: register))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.postUtteranceDelay = 0.2
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Speak a full dossier narrative aloud, the Lore+ "audio narration" of the
    /// deep dive (not just the 20-second scanner hook). Cancels any in-flight
    /// speech first and drives the same isSpeaking state so a button can toggle.
    func speakDossier(_ text: String) {
        offered = nil
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        configureSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.postUtteranceDelay = 0.15
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Dismiss the offer without speaking (the quiet-street / museum case).
    func dismissOffer() {
        offered = nil
    }

    /// Stop any in-flight narration (phone lowered, sheet opened, disappear).
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        offered = nil
        deactivateSession()
    }

    fileprivate func markStopped() {
        isSpeaking = false
        deactivateSession()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true, options: [])
    }

    /// Un-duck other apps once narration ends. A `.duckOthers` session must be
    /// explicitly deactivated or the user's music/podcast stays quiet forever.
    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// Thin `AVSpeechSynthesizerDelegate` bridge so `NarrationService` can stay a
/// clean `@Observable` value-facing type (the delegate can't be the
/// `@MainActor final class` itself without inheriting `NSObject`).
private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: NarrationService?

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in owner?.markStopped() }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in owner?.markStopped() }
    }
}
