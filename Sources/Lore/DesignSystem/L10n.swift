import Foundation
import Observation

/// Lightweight interface localization, ported from the scanner lab's nine
/// language dictionaries. "Auto" follows the device locale; an explicit pick
/// in Settings persists across launches. Story and culture CONTENT stays
/// English while translations are chronicled, and Settings says so honestly.
///
/// Coverage note: this pass localizes the app chrome (tabs, Settings, scanner
/// status). Deeper surface coverage extends key by key, the same dictionaries.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, es, fr, de, it, pt, ja, ko, zh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .pt: return "Português"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .zh: return "中文"
        }
    }
}

@Observable
final class L10n {
    static let shared = L10n()

    private static let storageKey = "lore.language.v1"

    /// "auto" or an `AppLanguage` rawValue; persisted.
    var choice: String {
        didSet { UserDefaults.standard.set(choice, forKey: Self.storageKey) }
    }

    init() {
        choice = UserDefaults.standard.string(forKey: Self.storageKey) ?? "auto"
    }

    /// The resolved interface language.
    var language: AppLanguage {
        if let explicit = AppLanguage(rawValue: choice) { return explicit }
        let device = Locale.current.language.languageCode?.identifier ?? "en"
        return AppLanguage(rawValue: device) ?? .en
    }

    /// Translate a key; falls back to English, then to the key itself.
    func t(_ key: String) -> String {
        Self.tables[language]?[key] ?? Self.tables[.en]?[key] ?? key
    }

    /// Convenience for call sites: `L10n.shared.t(key)`.
    static func t(_ key: String) -> String { shared.t(key) }

    // MARK: - Dictionaries (chrome keys)

    private static let tables: [AppLanguage: [String: String]] = [
        .en: [
            "tab.map": "Map", "tab.scanner": "Scanner", "tab.tours": "Tours",
            "tab.passport": "Passport", "tab.profile": "Profile",
            "settings.title": "Settings", "settings.language": "Language",
            "settings.languageAuto": "Auto (device)",
            "settings.languageNote": "Stories translate on your device into your language. Where a translation isn't available yet, the original English is shown.",
            "scan.permissionNeeded": "Location permission needed",
            "scan.findingBlock": "Finding your block…",
            "scan.findingNorth": "finding north…",
            "scan.coarseMode": "Coarse mode",
            "content.translated": "Translated on device",
            "dossier.gallery": "Gallery", "dossier.timeline": "Timeline",
            "dossier.streetView": "Street View", "dossier.sources": "Sources & links",
            "dossier.readMore": "Read more", "dossier.readLess": "Read less",
        ],
        .es: [
            "tab.map": "Mapa", "tab.scanner": "Escáner", "tab.tours": "Rutas",
            "tab.passport": "Pasaporte", "tab.profile": "Perfil",
            "settings.title": "Ajustes", "settings.language": "Idioma",
            "settings.languageAuto": "Automático (dispositivo)",
            "settings.languageNote": "Las historias se traducen en tu dispositivo a tu idioma. Cuando aún no hay traducción, se muestra el inglés original.",
            "scan.permissionNeeded": "Se necesita permiso de ubicación",
            "scan.findingBlock": "Buscando tu manzana…",
            "scan.findingNorth": "buscando el norte…",
            "scan.coarseMode": "Modo aproximado",
            "content.translated": "Traducido en el dispositivo",
            "dossier.gallery": "Galería", "dossier.timeline": "Cronología",
            "dossier.streetView": "Street View", "dossier.sources": "Fuentes y enlaces",
            "dossier.readMore": "Leer más", "dossier.readLess": "Leer menos",
        ],
        .fr: [
            "tab.map": "Carte", "tab.scanner": "Scanner", "tab.tours": "Circuits",
            "tab.passport": "Passeport", "tab.profile": "Profil",
            "settings.title": "Réglages", "settings.language": "Langue",
            "settings.languageAuto": "Auto (appareil)",
            "settings.languageNote": "Les histoires sont traduites dans votre langue sur votre appareil. Sans traduction disponible, l'anglais d'origine s'affiche.",
            "scan.permissionNeeded": "Autorisation de position requise",
            "scan.findingBlock": "Recherche de votre rue…",
            "scan.findingNorth": "recherche du nord…",
            "scan.coarseMode": "Mode approché",
            "content.translated": "Traduit sur l'appareil",
            "dossier.gallery": "Galerie", "dossier.timeline": "Chronologie",
            "dossier.streetView": "Street View", "dossier.sources": "Sources et liens",
            "dossier.readMore": "Lire plus", "dossier.readLess": "Lire moins",
        ],
        .de: [
            "tab.map": "Karte", "tab.scanner": "Scanner", "tab.tours": "Touren",
            "tab.passport": "Pass", "tab.profile": "Profil",
            "settings.title": "Einstellungen", "settings.language": "Sprache",
            "settings.languageAuto": "Automatisch (Gerät)",
            "settings.languageNote": "Geschichten werden auf deinem Gerät in deine Sprache übersetzt. Wo noch keine Übersetzung vorliegt, erscheint das englische Original.",
            "scan.permissionNeeded": "Standortberechtigung nötig",
            "scan.findingBlock": "Dein Block wird gesucht…",
            "scan.findingNorth": "Norden wird gesucht…",
            "scan.coarseMode": "Grober Modus",
            "content.translated": "Auf dem Gerät übersetzt",
            "dossier.gallery": "Galerie", "dossier.timeline": "Zeitleiste",
            "dossier.streetView": "Street View", "dossier.sources": "Quellen & Links",
            "dossier.readMore": "Mehr lesen", "dossier.readLess": "Weniger lesen",
        ],
        .it: [
            "tab.map": "Mappa", "tab.scanner": "Scanner", "tab.tours": "Itinerari",
            "tab.passport": "Passaporto", "tab.profile": "Profilo",
            "settings.title": "Impostazioni", "settings.language": "Lingua",
            "settings.languageAuto": "Automatica (dispositivo)",
            "settings.languageNote": "Le storie vengono tradotte sul tuo dispositivo nella tua lingua. Dove non c'è ancora una traduzione, viene mostrato l'inglese originale.",
            "scan.permissionNeeded": "Serve il permesso di posizione",
            "scan.findingBlock": "Cerco il tuo isolato…",
            "scan.findingNorth": "cerco il nord…",
            "scan.coarseMode": "Modalità approssimata",
            "content.translated": "Tradotto sul dispositivo",
            "dossier.gallery": "Galleria", "dossier.timeline": "Cronologia",
            "dossier.streetView": "Street View", "dossier.sources": "Fonti e link",
            "dossier.readMore": "Leggi altro", "dossier.readLess": "Leggi meno",
        ],
        .pt: [
            "tab.map": "Mapa", "tab.scanner": "Scanner", "tab.tours": "Roteiros",
            "tab.passport": "Passaporte", "tab.profile": "Perfil",
            "settings.title": "Ajustes", "settings.language": "Idioma",
            "settings.languageAuto": "Automático (aparelho)",
            "settings.languageNote": "As histórias são traduzidas no seu aparelho para o seu idioma. Onde ainda não há tradução, o inglês original é exibido.",
            "scan.permissionNeeded": "Permissão de localização necessária",
            "scan.findingBlock": "Encontrando seu quarteirão…",
            "scan.findingNorth": "procurando o norte…",
            "scan.coarseMode": "Modo aproximado",
            "content.translated": "Traduzido no aparelho",
            "dossier.gallery": "Galeria", "dossier.timeline": "Linha do tempo",
            "dossier.streetView": "Street View", "dossier.sources": "Fontes e links",
            "dossier.readMore": "Ler mais", "dossier.readLess": "Ler menos",
        ],
        .ja: [
            "tab.map": "マップ", "tab.scanner": "スキャナー", "tab.tours": "ツアー",
            "tab.passport": "パスポート", "tab.profile": "プロフィール",
            "settings.title": "設定", "settings.language": "言語",
            "settings.languageAuto": "自動（端末の設定）",
            "settings.languageNote": "物語はお使いの端末でお使いの言語に翻訳されます。翻訳がまだない場合は英語の原文が表示されます。",
            "scan.permissionNeeded": "位置情報の許可が必要です",
            "scan.findingBlock": "現在地を確認中…",
            "scan.findingNorth": "北を探しています…",
            "scan.coarseMode": "粗密モード",
            "content.translated": "端末で翻訳済み",
            "dossier.gallery": "ギャラリー", "dossier.timeline": "年表",
            "dossier.streetView": "ストリートビュー", "dossier.sources": "出典とリンク",
            "dossier.readMore": "続きを読む", "dossier.readLess": "折りたたむ",
        ],
        .ko: [
            "tab.map": "지도", "tab.scanner": "스캐너", "tab.tours": "투어",
            "tab.passport": "여권", "tab.profile": "프로필",
            "settings.title": "설정", "settings.language": "언어",
            "settings.languageAuto": "자동(기기 설정)",
            "settings.languageNote": "이야기는 기기에서 사용 중인 언어로 번역됩니다. 아직 번역이 없는 경우 원문(영어)이 표시됩니다.",
            "scan.permissionNeeded": "위치 권한이 필요합니다",
            "scan.findingBlock": "현재 블록 찾는 중…",
            "scan.findingNorth": "북쪽을 찾는 중…",
            "scan.coarseMode": "대략 모드",
            "content.translated": "기기에서 번역됨",
            "dossier.gallery": "갤러리", "dossier.timeline": "연표",
            "dossier.streetView": "스트리트 뷰", "dossier.sources": "출처 및 링크",
            "dossier.readMore": "더 보기", "dossier.readLess": "접기",
        ],
        .zh: [
            "tab.map": "地图", "tab.scanner": "扫描", "tab.tours": "路线",
            "tab.passport": "护照", "tab.profile": "我的",
            "settings.title": "设置", "settings.language": "语言",
            "settings.languageAuto": "自动（跟随设备）",
            "settings.languageNote": "故事会在你的设备上翻译成你的语言。暂无翻译时显示英文原文。",
            "scan.permissionNeeded": "需要定位权限",
            "scan.findingBlock": "正在定位街区…",
            "scan.findingNorth": "正在寻找北方…",
            "scan.coarseMode": "粗略模式",
            "content.translated": "已在设备上翻译",
            "dossier.gallery": "图库", "dossier.timeline": "时间线",
            "dossier.streetView": "街景", "dossier.sources": "来源与链接",
            "dossier.readMore": "阅读更多", "dossier.readLess": "收起",
        ],
    ]
}
