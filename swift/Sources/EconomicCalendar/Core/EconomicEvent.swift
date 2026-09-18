import CryptoKit
import Foundation

/// Importance of an economic event, mirroring investing.com's bull-icon scale.
/// Port of `models.ImportanceLevel`.
enum Importance: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3

    static func < (lhs: Importance, rhs: Importance) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Mirrors `ImportanceLevel.from_bull_count`.
    init(bullCount: Int) {
        self = bullCount >= 3 ? .high : (bullCount == 2 ? .medium : .low)
    }

    /// Mirrors `ImportanceLevel.from_label` ('low'/'medium'/'high', case-insensitive).
    init(label: String) {
        let key = label.trimmingCharacters(in: .whitespaces).uppercased()
        switch key {
        case "LOW": self = .low
        case "MEDIUM": self = .medium
        case "HIGH": self = .high
        default:
            self = Importance(rawValue: Int(key) ?? 0) ?? .low
        }
    }

    var label: String {
        switch self {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }

    var capitalizedLabel: String { label.capitalized }
}

/// A single row from the investing.com economic calendar.
/// Port of `models.EconomicEvent`. `time` is an absolute instant; all display
/// and parsing uses Asia/Shanghai, mirroring the legacy `LOCAL_TZ` behavior.
///
/// Events without a fixed release time ("All Day" / "Tentative") carry
/// `timeLabel` (the site's own wording) and a `time` of that day's midnight —
/// sorted to the top of their day like investing.com does, never notified.
struct EconomicEvent: Identifiable, Sendable, Equatable {
    let id: String
    let time: Date
    let currency: String
    let importance: Importance
    let name: String
    let actual: String?
    let forecast: String?
    let previous: String?
    let sourceURL: String
    let timeLabel: String?

    /// Display string for the time column.
    var timeText: String { timeLabel ?? Theme.hhmm(time) }

    var isHighImpact: Bool { importance == .high }
}

/// On-disk representation of one event, matching the legacy Python cache.json
/// field names exactly (`source_url` snake_case, ISO strings for dates).
struct EventDTO: Codable, Sendable {
    var id: String
    var time: String
    var currency: String
    var importance: Int
    var name: String
    var actual: String?
    var forecast: String?
    var previous: String?
    var source_url: String
    var time_label: String?
}

/// Legacy cache envelope: `{"fetched_at": iso, "events": [...]}`.
struct CacheEnvelopeDTO: Codable, Sendable {
    var fetched_at: String
    var events: [EventDTO]
}

extension EconomicEvent {
    var dto: EventDTO {
        EventDTO(
            id: id,
            time: EventParsing.formatISODate(time, fractional: false),
            currency: currency,
            importance: importance.rawValue,
            name: name,
            actual: actual,
            forecast: forecast,
            previous: previous,
            source_url: sourceURL,
            time_label: timeLabel
        )
    }

    init?(dto: EventDTO) {
        guard let time = EventParsing.parseISODate(dto.time) else { return nil }
        self.init(
            id: dto.id,
            time: time,
            currency: dto.currency,
            importance: Importance(rawValue: dto.importance) ?? .low,
            name: dto.name,
            actual: dto.actual,
            forecast: dto.forecast,
            previous: dto.previous,
            sourceURL: dto.source_url,
            timeLabel: dto.time_label
        )
    }
}
