import Foundation

/// JSON-backed cache of fetched events — same cache.json format as the Python
/// app. Atomic writes; read failures return nil (UI falls back gracefully).
actor CacheStore {
    struct Snapshot: Sendable {
        let fetchedAt: Date?
        let events: [EconomicEvent]
    }

    private let path: String

    init(path: String) {
        self.path = path
    }

    func read() -> Snapshot? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
            let envelope = try JSONDecoder().decode(CacheEnvelopeDTO.self, from: data)
            let fetchedAt = EventParsing.parseISODate(envelope.fetched_at)
            // Tolerant: skip events with unparsable times instead of failing wholesale.
            let events = envelope.events.compactMap(EconomicEvent.init(dto:)).sorted { $0.time < $1.time }
            return Snapshot(fetchedAt: fetchedAt, events: events)
        } catch {
            AppLog.shared.error("Failed to read cache: \(error.localizedDescription)")
            return nil
        }
    }

    func write(events: [EconomicEvent], fetchedAt: Date) {
        let envelope = CacheEnvelopeDTO(
            fetched_at: EventParsing.formatISODate(fetchedAt, fractional: true),
            events: events.map(\.dto)
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(envelope)
            let tmp = path + ".tmp"
            try data.write(to: URL(fileURLWithPath: tmp))
            _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
        } catch {
            AppLog.shared.error("Failed to write cache: \(error.localizedDescription)")
        }
    }
}

/// JSON-backed store of already-notified event IDs — same notified.json format
/// as the Python app, so dedup state survives the rewrite. Atomic writes.
actor NotifiedStore {
    struct Entry: Codable, Sendable {
        var notified_at: String
    }

    private let path: String
    private var state: [String: Entry]

    init(path: String) {
        self.path = path
        if let data = FileManager.default.contents(atPath: path),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            state = decoded
        } else {
            state = [:]
        }
    }

    func isNotified(_ eventID: String) -> Bool {
        state[eventID] != nil
    }

    func markNotified(_ eventID: String, at date: Date) {
        state[eventID] = Entry(notified_at: EventParsing.formatISODate(date, fractional: false))
        save()
    }

    /// Remove entries older than `days`; unparseable entries are kept (parity).
    func purge(olderThanDays days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var purged = 0
        var keep: [String: Entry] = [:]
        for (id, entry) in state {
            if let ts = EventParsing.parseISODate(entry.notified_at), ts >= cutoff {
                keep[id] = entry
            } else if EventParsing.parseISODate(entry.notified_at) == nil {
                keep[id] = entry
            } else {
                purged += 1
            }
        }
        guard purged > 0 else { return }
        state = keep
        save()
        AppLog.shared.info("Purged \(purged) notified entries older than \(days)d")
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(state)
            let tmp = path + ".tmp"
            try data.write(to: URL(fileURLWithPath: tmp))
            _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
        } catch {
            AppLog.shared.error("Failed to save notified state: \(error.localizedDescription)")
        }
    }
}
