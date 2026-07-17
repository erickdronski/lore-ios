import SwiftUI

/// The small, tasteful set of families a real offer can belong to. Kept
/// deliberately minimal — this is an explorer's field guide, not an ad grid.
/// Each family is a quiet line item with one glyph and a plain label; the
/// `category` string comes from the deal source (`deal_source.category`).
enum OfferCategory: CaseIterable, Identifiable, Hashable {
    case tours      // guided experiences, walking tours, day trips
    case pass       // city passes, museum admission bundles
    case stay       // hotels & places to stay nearby
    case dine       // restaurant reservations
    case drive      // car rentals, getting around
    case connect    // travel eSIM / data
    case local      // curated local finds (default)

    init(_ raw: String) {
        switch raw.lowercased() {
        case "tours", "tour", "experiences", "attractions": self = .tours
        case "pass", "passes", "admission", "tickets": self = .pass
        case "stay", "hotel", "hotels", "lodging": self = .stay
        case "dine", "dining", "food", "restaurant", "restaurants": self = .dine
        case "drive", "car", "cars", "rental", "transport": self = .drive
        case "connect", "esim", "data", "sim": self = .connect
        default: self = .local
        }
    }

    var id: String { label }

    /// SF Symbol — single-weight, monochrome, no color-coding. Restraint is
    /// the whole point: these read as editorial marks, not banners.
    var icon: String {
        switch self {
        case .tours:   return "figure.walk"
        case .pass:    return "ticket"
        case .stay:    return "bed.double"
        case .dine:    return "fork.knife"
        case .drive:   return "car"
        case .connect: return "simcard"
        case .local:   return "mappin.and.ellipse"
        }
    }

    /// A single word for the free-teaser preview chips — tighter than `label`.
    var teaserWord: String {
        switch self {
        case .tours:   return "Tours"
        case .pass:    return "Passes"
        case .stay:    return "Stay"
        case .dine:    return "Dine"
        case .drive:   return "Cars"
        case .connect: return "eSIM"
        case .local:   return "Local"
        }
    }

    /// The section header shown above this family's offers.
    var label: String {
        switch self {
        case .tours:   return "Tours & experiences"
        case .pass:    return "Passes & admission"
        case .stay:    return "Places to stay"
        case .dine:    return "Dining"
        case .drive:   return "Getting around"
        case .connect: return "Stay connected"
        case .local:   return "Local finds"
        }
    }

    /// Stable display order — experiences first (closest to Lore's soul),
    /// utilities (drive/connect) last.
    var order: Int {
        switch self {
        case .tours:   return 0
        case .pass:    return 1
        case .stay:    return 2
        case .dine:    return 3
        case .drive:   return 4
        case .connect: return 5
        case .local:   return 6
        }
    }
}
