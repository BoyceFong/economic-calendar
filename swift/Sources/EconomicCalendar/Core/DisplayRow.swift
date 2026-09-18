import Foundation

/// One visible row of data for an event, pre-computed so views stay dumb.
struct EventRowData: Identifiable, Sendable {
    let event: EconomicEvent
    let isAlt: Bool

    var id: String { event.id }
}

/// The flat row list rendered by the list view. The current-time divider is a
/// real list element inserted BETWEEN two events, so it can never cover
/// content and snaps to item boundaries by construction.
///
/// Insertion rule (index = first event with time >= now):
///   - now before all events → divider at the very top
///   - normal case           → divider between the two neighboring items
///   - now after all events  → divider at the very bottom
enum DisplayRow: Identifiable {
    case event(EventRowData)
    case nowDivider(Date)

    var id: String {
        switch self {
        case .event(let data): data.id
        case .nowDivider: "now-divider"
        }
    }

    static let dividerID = "now-divider"

    static func buildRows(events: [EconomicEvent], now: Date) -> [DisplayRow] {
        guard !events.isEmpty else { return [] }
        let index = events.firstIndex { $0.time >= now } ?? events.count
        var rows: [DisplayRow] = []
        for (i, event) in events.enumerated() {
            if i == index { rows.append(.nowDivider(now)) }
            rows.append(.event(EventRowData(event: event, isAlt: i % 2 == 1)))
        }
        if index == events.count { rows.append(.nowDivider(now)) }
        return rows
    }

    /// Where the divider sits relative to the list — drives auto-scroll anchors.
    enum Position {
        case aboveAll
        case middle
        case belowAll
    }

    static func dividerPosition(in rows: [DisplayRow]) -> Position? {
        guard let idx = rows.firstIndex(where: { if case .nowDivider = $0 { return true } else { return false } }) else { return nil }
        if idx == 0 { return .aboveAll }
        if idx == rows.count - 1 { return .belowAll }
        return .middle
    }
}
