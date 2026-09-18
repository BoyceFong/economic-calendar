import Foundation

/// CLI helper mirroring `python -m fetcher --dry-run`'s table print — decodes
/// cache.json and prints it without any UI.
enum PrintCacheTool {
    /// Self-checks for the parsing logic (also a regression net for upgrades).
    static func parseTest() {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "PASS" : "FAIL")  \(name)")
            if !condition { failures += 1 }
        }

        let ymd = EventParsing.parseDateHeader("Thursday, September 17, 2026")
        check("parseDateHeader", ymd?.year == 2026 && ymd?.month == 9 && ymd?.day == 17)

        // Isolate: regex match vs month-table lookup.
        let probe = "Thursday, September 17, 2026"
        let dateHeaderRegex = /([A-Z][a-z]+),\s+([A-Z][a-z]+)\s+(\d{1,2}),?\s+(\d{4})/
        if let m = probe.firstMatch(of: dateHeaderRegex) {
            print("      regex groups: [\(m.1)] [\(m.2)] [\(m.3)] [\(m.4)]")
        } else {
            print("      regex did NOT match")
        }

        let t = EventParsing.parseEventTime("01:00 PM", year: 2026, month: 9, day: 17)
        check("parseEventTime PM", Theme.hhmm(t) == "13:00")

        check("resolveCurrency US", EventParsing.resolveCurrency("US") == "USD")
        check("resolveCurrency DE", EventParsing.resolveCurrency("DE") == "EUR")

        check("eventID parity", EventParsing.makeEventID(
            currency: "USD",
            name: "U.S. Baker Hughes Oil Rig Count",
            date: "Saturday, August 1, 2026",
            time: "01:00") == "1b1e565cbc47")

        // End-to-end: parse one realistic raw row and expect it to pass filters.
        let row = RawRow(date: "Thursday, September 17, 2026", time: "01:00", countryCode: "US",
                         bull: 2, name: "Test Event", url: "", actual: "1", forecast: "2", previous: "3")
        let now = EventParsing.parseISODate("2026-09-17T12:00:00+08:00")!
        let events = EventParsing.parseRawRows(
            [row], fallbackURL: "", currencies: ["USD", "EUR"], minImportance: .low,
            now: now, dateRangeDays: 2)
        check("parseRawRows end-to-end", events.count == 1)

        if failures > 0 { exit(1) }
        print("All parse tests passed")
    }
    static func run() {
        let path = AppPaths.cacheFile
        guard let data = FileManager.default.contents(atPath: path) else {
            print("(no cache at \(path))")
            return
        }
        do {
            let envelope = try JSONDecoder().decode(CacheEnvelopeDTO.self, from: data)
            let events = envelope.events.compactMap(EconomicEvent.init(dto:))
            print("Fetched at: \(envelope.fetched_at)")
            print()
            printTable(events)
        } catch {
            print("Failed to decode \(path): \(error)")
        }
    }

    private static let tableTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.timeZone = EventParsing.localTimeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func printTable(_ events: [EconomicEvent]) {
        if events.isEmpty {
            print("(no events)")
            return
        }
        let headers = ["Time", "Cur", "Imp", "Event", "Actual", "Forecast", "Previous"]
        var rows: [[String]] = []
        for e in events {
            rows.append([
                tableTimeFormatter.string(from: e.time),
                e.currency,
                e.importance.capitalizedLabel,
                String(e.name.prefix(55)),
                e.actual ?? "",
                e.forecast ?? "",
                e.previous ?? "",
            ])
        }
        let all = [headers] + rows
        let widths = (0..<headers.count).map { col in all.map { $0[col].count }.max() ?? 0 }
        func padded(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }
        func line(_ cells: [String]) -> String {
            cells.enumerated().map { padded($1, widths[$0]) }.joined(separator: "  ")
        }
        print(line(headers))
        print(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
        for row in rows {
            print(line(row))
        }
    }
}
