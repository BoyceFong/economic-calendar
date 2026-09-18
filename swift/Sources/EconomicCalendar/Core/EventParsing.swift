import CryptoKit
import Foundation

/// Raw row object produced by the in-page extraction JS (ExtractCalendar.js).
struct RawRow: Codable, Sendable {
    var date: String
    var time: String
    var countryCode: String
    var bull: Int
    var name: String
    var url: String
    var actual: String?
    var forecast: String?
    var previous: String?
}

/// Parsing / filtering helpers. One-to-one port of the Python logic in
/// `fetcher.py` and `models.py` so cached data and event ids stay compatible.
enum EventParsing {
    /// Legacy `models.LOCAL_TZ`.
    static let localTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    // MARK: - Dates

    private nonisolated(unsafe) static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()

    private static let isoNaive: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = localTimeZone
        return f
    }()

    /// Tolerant ISO-8601 parse: fractional seconds optional, tz offset optional
    /// (naive strings are assumed Asia/Shanghai, mirroring `EconomicEvent.from_dict`).
    static func parseISODate(_ string: String) -> Date? {
        if let d = isoWithFraction.date(from: string) { return d }
        if let d = isoPlain.date(from: string) { return d }
        if let d = isoNaive.date(from: string) { return d }
        return nil
    }

    /// Python `datetime.isoformat()`-style output. `fractional` mirrors whether
    /// microseconds were present (cache `fetched_at` has them, event times don't).
    static func formatISODate(_ date: Date, fractional: Bool) -> String {
        let f = fractional ? isoWithFractionOut : isoPlainOut
        return f.string(from: date)
    }

    private nonisolated(unsafe) static let isoPlainOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private nonisolated(unsafe) static let isoWithFractionOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Page parsing (port of fetcher.py helpers)

    /// "Weekday, Month D, YYYY" header regex — port of `DATE_HEADER_RE`.
    private nonisolated(unsafe) static let dateHeaderRegex = /([A-Z][a-z]+),\s+([A-Z][a-z]+)\s+(\d{1,2}),?\s+(\d{4})/

    /// Port of `MONTHS` (full names + the abbreviations the site emits).
    private static let months: [String: Int] = [
        "January": 1, "February": 2, "March": 3, "April": 4,
        "May": 5, "June": 6, "July": 7, "August": 8,
        "September": 9, "October": 10, "November": 11, "December": 12,
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "Jun": 6,
        "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
    ]

    /// Port of `_parse_date_header`.
    static func parseDateHeader(_ text: String) -> (year: Int, month: Int, day: Int)? {
        guard let m = text.firstMatch(of: dateHeaderRegex) else { return nil }
        // Groups: 1 = weekday, 2 = month name, 3 = day, 4 = year.
        var monthName = String(m.2)
        monthName = monthName.prefix(1).capitalized + monthName.dropFirst().lowercased()
        guard let month = months[monthName] else { return nil }
        return (Int(m.4) ?? 0, month, Int(m.3) ?? 0)
    }

    /// "H:MM" / "H:MM AM/PM" → instant. Port of `_parse_time`.
    static func parseEventTime(_ text: String, year: Int, month: Int, day: Int) -> Date {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let timeRegex = /^(\d{1,2}):(\d{2})(?:\s*(AM|PM|am|pm))?/
        var hour = 0
        var minute = 0
        if let m = trimmed.firstMatch(of: timeRegex) {
            hour = Int(m.1) ?? 0
            minute = Int(m.2) ?? 0
            let ampm = m.3.map { $0.uppercased() } ?? ""
            if ampm == "PM" && hour < 12 { hour += 12 }
            else if ampm == "AM" && hour == 12 { hour = 0 }
        }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = localTimeZone
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    /// Port of `_make_event_id`: md5("{currency}|{name}|{date}|{time}"), first 12 hex chars.
    /// Must stay byte-identical so notified.json dedup survives the rewrite.
    static func makeEventID(currency: String, name: String, date: String, time: String) -> String {
        let raw = "\(currency)|\(name)|\(date)|\(time)"
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    /// Port of `_resolve_currency`.
    static func resolveCurrency(_ countryCode: String) -> String {
        let cc = countryCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cc.isEmpty else { return "" }
        if let mapped = CountryMaps.countryToCurrency[cc] { return mapped }
        if cc.count == 3 { return cc }
        if cc == "EU" { return "EUR" }
        return cc
    }

    /// Port of `_passes_filters` (fetch-time filtering from config).
    static func passesFetchFilters(
        _ event: EconomicEvent,
        currencies: Set<String>,
        minImportance: Importance,
        now: Date,
        dateRangeDays: Int
    ) -> Bool {
        if !currencies.isEmpty && !currencies.contains(event.currency.uppercased()) {
            return false
        }
        if event.importance < minImportance { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = localTimeZone
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: now),
              let horizon = cal.date(byAdding: .day, value: dateRangeDays, to: cal.startOfDay(for: now))
        else { return false }
        let start = cal.startOfDay(for: yesterday)
        return start <= event.time && event.time <= horizon
    }

    /// Port of `_parse_row` + fetch-time filtering + time sort.
    static func parseRawRows(
        _ rows: [RawRow],
        fallbackURL: String,
        currencies: Set<String>,
        minImportance: Importance,
        now: Date,
        dateRangeDays: Int
    ) -> [EconomicEvent] {
        var events: [EconomicEvent] = []
        for row in rows {
            let currency = resolveCurrency(row.countryCode)
            guard !currency.isEmpty else { continue }
            guard let ymd = parseDateHeader(row.date) else { continue }
            let time = parseEventTime(row.time, year: ymd.year, month: ymd.month, day: ymd.day)
            let name = row.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let bull = row.bull == 0 ? 1 : row.bull
            let event = EconomicEvent(
                id: makeEventID(currency: currency, name: name, date: row.date, time: row.time),
                time: time,
                currency: currency,
                importance: Importance(bullCount: bull),
                name: name,
                actual: row.actual,
                forecast: row.forecast,
                previous: row.previous,
                sourceURL: row.url.isEmpty ? fallbackURL : row.url
            )
            if passesFetchFilters(event, currencies: currencies, minImportance: minImportance, now: now, dateRangeDays: dateRangeDays) {
                events.append(event)
            }
        }
        events.sort { $0.time < $1.time }
        return events
    }

    // MARK: - Display helpers (port of widget.py)

    /// Port of `_try_float`: strips "%" and "," then parses.
    static func tryFloat(_ text: String?) -> Double? {
        guard let text, !text.isEmpty else { return nil }
        var cleaned = text
        for ch in ["%", ",", " "] { cleaned = cleaned.replacingOccurrences(of: ch, with: "") }
        return Double(cleaned)
    }
}
