import AVFoundation
import Observation

/// Audio-first, hands-free narration for the scanner (docs/12 §3.2): resolving
/// a Tier-A pin can **auto-offer** the ~20-second narrated hook so a walker
/// never has to read while moving. "Keep walking, I'll tell you" is the docent
/// mode, the phone talks and the user looks up at the actual building, the
/// accessibility win *and* the magic moment.
///
/// The paid-quality path is pre-rendered studio audio from the `narration`
/// bucket. When a city still lacks that asset, the fallback deliberately chooses
/// the best installed iOS voice and a slower docent cadence instead of the raw
/// system default. The hook text comes from the place's Layer-1 (CC0/PD, safe
/// to speak without attribution, docs/04 §2.2). Auto-offer etiquette is the
/// open question (docs/12 open Q4): we *offer* on lock and let the user start it
/// — we do not auto-*play*, which would be intrusive on a quiet street or in a
/// museum. The one-tap start is `speak(_:)`.
@Observable
@MainActor
final class NarrationService {
    /// The place currently being offered narration, if any. Drives the
    /// "Keep walking, I'll tell you" affordance in the scanner.
    private(set) var offered: Place?
    /// True while the synthesizer is actively speaking.
    private(set) var isSpeaking = false
    /// True when an active narration is paused and can be resumed in place.
    private(set) var isPaused = false
    /// Actionable playback failure copy for the owning surface.
    private(set) var playbackError: String?
    /// Current narration speed. Studio audio updates immediately; TTS uses the
    /// selected speed on its next utterance.
    private(set) var playbackRate: Float = 1
    var isActive: Bool { isSpeaking || isPaused }
    var canSeek: Bool { player != nil }
    /// Identifies a short UI utterance so only its originating card shows Stop.
    private(set) var activeSpeechID: String?
    /// The place we last auto-offered, so a re-lock on the same building
    /// doesn't re-nag (docs/12 open Q4 etiquette).
    private var lastOfferedID: String?

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechDelegate()
    private var activeUtterance: AVSpeechUtterance?

    /// Player for pre-rendered studio narration (the `narration` bucket).
    private var player: AVPlayer?
    private var playerObservers: [NSObjectProtocol] = []
    private var itemStatusObservation: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var wasInterruptedWhileActive = false
    /// Fallback text if the audio file fails mid-flight (offline, moved).
    private var fallbackText: String?

    init() {
        delegate.owner = self
        synthesizer.delegate = delegate
        observeAudioSession()
    }

    /// The ~20-second hook line for a place, docent voice. Prefers the authored
    /// public teaser; falls back to a persona-flavored orienting line built
    /// from the place's own facts (never invents history, only reads what's
    /// there).
    static func hookText(for place: Place, register: String) -> String {
        if let teaser = place.teaser {
            return teaser
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
        activeSpeechID = nil
        // Cancel any in-flight hook so a new lock speaks now, not queued behind
        // the old one (AVSpeechSynthesizer enqueues by default).
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        playbackError = nil
        configureSession()
        let utterance = AVSpeechUtterance(string: Self.hookText(for: place, register: register))
        utterance.voice = Self.docentVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.84 * playbackRate
        utterance.pitchMultiplier = 0.96
        utterance.volume = 0.95
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.25
        activeUtterance = utterance
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    /// Speak a full dossier narrative aloud, the Lore+ "audio narration" of the
    /// deep dive (not just the 20-second scanner hook). Cancels any in-flight
    /// speech first and drives the same isSpeaking state so a button can toggle.
    func speakDossier(_ text: String) {
        offered = nil
        activeSpeechID = nil
        guard !text.isEmpty else { return }
        stopPlayback()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        playbackError = nil
        configureSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.docentVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82 * playbackRate
        utterance.pitchMultiplier = 0.96
        utterance.volume = 0.95
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.2
        activeUtterance = utterance
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    /// Speak a traveler phrase with the closest matching on-device voice.
    /// Devices without that voice gracefully use the system default.
    func speakPhrase(_ text: String, languageName: String?, id: String) {
        guard !text.isEmpty else { return }
        stopPlayback()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        playbackError = nil
        configureSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(matching: languageName)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.84 * playbackRate
        utterance.pitchMultiplier = 0.98
        utterance.volume = 0.95
        utterance.postUtteranceDelay = 0.1
        activeUtterance = utterance
        activeSpeechID = id
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    /// Narrate a dossier the best way available: the pre-rendered studio audio
    /// when the dive has one, else on-device TTS. One entry point so every
    /// Listen button upgrades automatically as cities gain generated audio.
    func narrateDossier(text: String?, audioURL: URL?) {
        if let audioURL {
            playDossierAudio(audioURL, fallbackText: text)
        } else if let text {
            speakDossier(text)
        }
    }

    /// Play a pre-rendered narration file, driving the same `isSpeaking` state
    /// as TTS so toggle buttons work unchanged. On a playback failure (offline
    /// and unpinned, file moved) it falls back to speaking `fallbackText` so
    /// the Listen button never silently does nothing.
    func playDossierAudio(_ url: URL, fallbackText: String? = nil) {
        offered = nil
        activeSpeechID = nil
        activeUtterance = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        stopPlayback()
        playbackError = nil
        configureSession()
        self.fallbackText = fallbackText

        // A downloaded city pack keeps narration files on disk; play the local
        // copy when one exists so audio tours work in the subway.
        let resolved = PackImageStore.localURL(for: url) ?? url
        let item = AVPlayerItem(url: resolved)
        let player = AVPlayer(playerItem: item)
        self.player = player
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.handlePlaybackFailure() }
        }

        playerObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopPlayback()
                self?.markStopped()
            }
        })
        playerObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackFailure() }
        })

        isSpeaking = true
        isPaused = false
        player.playImmediately(atRate: playbackRate)
    }

    /// Pause without losing the listener's place. Works for both studio files
    /// and on-device speech, and keeps the background audio session alive.
    func pause() {
        guard isSpeaking else { return }
        let didPause: Bool
        if let player {
            player.pause()
            didPause = true
        } else {
            didPause = synthesizer.pauseSpeaking(at: .word)
        }
        guard didPause else { return }
        isSpeaking = false
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        configureSession()
        let didResume: Bool
        if let player {
            player.playImmediately(atRate: playbackRate)
            didResume = true
        } else {
            didResume = synthesizer.continueSpeaking()
        }
        guard didResume else { return }
        isPaused = false
        isSpeaking = true
    }

    /// Seek studio narration while clamping to the playable timeline. TTS does
    /// not expose a safe time cursor, so the UI hides seek controls for it.
    func skip(seconds: Double) {
        guard let player, let item = player.currentItem else { return }
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        let duration = item.duration.seconds
        let upper = duration.isFinite ? max(duration - 0.25, 0) : current + max(seconds, 0)
        let target = min(max(current + seconds, 0), upper)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func cyclePlaybackRate() {
        let rates: [Float] = [0.85, 1, 1.2, 1.5]
        let index = rates.firstIndex(of: playbackRate) ?? 1
        playbackRate = rates[(index + 1) % rates.count]
        if let player, !isPaused {
            player.playImmediately(atRate: playbackRate)
        }
    }

    /// Audio file died mid-flight: degrade to TTS of the same narrative rather
    /// than ending in silence (the fallback is the old baseline, never worse).
    private func handlePlaybackFailure() {
        guard player != nil else { return }
        let text = fallbackText
        stopPlayback()
        if let text, !text.isEmpty {
            fallbackText = nil
            speakDossier(text)
            playbackError = "Studio audio was unavailable, so Lore switched to the on-device narrator."
        } else {
            playbackError = "This narration couldn't be played. Try again when you have a connection."
            markStopped()
        }
    }

    /// Tear down the player + its observers (idempotent).
    private func stopPlayback() {
        for observer in playerObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        playerObservers.removeAll()
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        player?.pause()
        player = nil
    }

    /// Dismiss the offer without speaking (the quiet-street / museum case).
    func dismissOffer() {
        offered = nil
    }

    /// Stop any in-flight narration (phone lowered, sheet opened, disappear).
    func stop() {
        stopPlayback()
        activeUtterance = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        isPaused = false
        activeSpeechID = nil
        offered = nil
        fallbackText = nil
        deactivateSession()
    }

    fileprivate func markStopped() {
        isSpeaking = false
        isPaused = false
        activeUtterance = nil
        activeSpeechID = nil
        fallbackText = nil
        deactivateSession()
    }

    fileprivate func speechDidStop(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        markStopped()
    }

    nonisolated static func voiceQualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium:
            return 3
        case .enhanced:
            return 2
        case .default:
            return 1
        @unknown default:
            return 0
        }
    }

    /// Ranks installed voices for Lore's fallback narrator. Quality stays the
    /// first-order signal, then exact locale, then voices that tend to be the
    /// natural Siri/Ava/Samantha-style options. Novelty voices are deliberately
    /// penalized so a device with playful voices installed never sounds like a
    /// gimmick when the city lacks studio audio.
    nonisolated static func voiceSelectionScore(
        quality: AVSpeechSynthesisVoiceQuality,
        name: String,
        language: String,
        exactLanguages: Set<String> = []
    ) -> Int {
        let foldedName = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en")
        )
        var score = voiceQualityRank(quality) * 1_000
        if exactLanguages.contains(language) { score += 150 }
        if language == "en-US" { score += 40 }
        if ["en-GB", "en-AU", "en-CA"].contains(language) { score += 24 }

        let premiumDocentNames = [
            "siri", "ava", "samantha", "allison", "joelle", "karen",
            "daniel", "arthur", "martha", "moira", "tessa", "serena"
        ]
        if let index = premiumDocentNames.firstIndex(where: { foldedName.contains($0) }) {
            score += max(30, 120 - index * 6)
        }

        let noveltyNames = [
            "bahh", "bells", "boing", "bubbles", "cellos", "good news",
            "bad news", "jester", "organ", "superstar", "trinoids",
            "whisper", "zarvox", "hysterical", "deranged", "wobble"
        ]
        if noveltyNames.contains(where: { foldedName.contains($0) }) {
            score -= 500
        }
        return score
    }

    private static func docentVoice() -> AVSpeechSynthesisVoice? {
        preferredVoice(for: ["en-US", "en-GB", "en-AU", "en-CA"]) ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func voice(matching languageName: String?) -> AVSpeechSynthesisVoice? {
        guard let languageName else { return nil }
        let english = Locale(identifier: "en")
        let requested = languageName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: english
        )

        let matches = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            guard let code = Locale(identifier: voice.language).language.languageCode?.identifier,
                  let localizedName = english.localizedString(forLanguageCode: code) else {
                return false
            }
            let candidate = localizedName.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: english
            )
            return requested.contains(candidate) || candidate.contains(requested)
        }
        return preferredVoice(from: matches)
    }

    private static func preferredVoice(for languages: [String]) -> AVSpeechSynthesisVoice? {
        let languageCodes = Set(languages.compactMap {
            Locale(identifier: $0).language.languageCode?.identifier
        })
        let matches = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            languages.contains(voice.language) ||
            Locale(identifier: voice.language).language.languageCode.map { languageCodes.contains($0.identifier) } == true
        }
        return preferredVoice(from: matches, exactLanguages: Set(languages))
    }

    private static func preferredVoice(
        from voices: [AVSpeechSynthesisVoice],
        exactLanguages: Set<String> = []
    ) -> AVSpeechSynthesisVoice? {
        voices.sorted { lhs, rhs in
            let lhsScore = voiceSelectionScore(
                quality: lhs.quality,
                name: lhs.name,
                language: lhs.language,
                exactLanguages: exactLanguages
            )
            let rhsScore = voiceSelectionScore(
                quality: rhs.quality,
                name: rhs.name,
                language: rhs.language,
                exactLanguages: exactLanguages
            )
            if lhsScore != rhsScore { return lhsScore > rhsScore }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }.first
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            playbackError = "Audio couldn't take control of the speaker. Check silent output or Bluetooth and try again."
        }
    }

    /// Un-duck other apps once narration ends. A `.duckOthers` session must be
    /// explicitly deactivated or the user's music/podcast stays quiet forever.
    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleRouteChange(note) }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
            wasInterruptedWhileActive = isActive
            pause()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            if wasInterruptedWhileActive && shouldResume { resume() }
            wasInterruptedWhileActive = false
        @unknown default:
            wasInterruptedWhileActive = false
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }
        pause()
        playbackError = "Audio paused because your headphones or speaker disconnected."
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
        Task { @MainActor in owner?.speechDidStop(utterance) }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in owner?.speechDidStop(utterance) }
    }
}
