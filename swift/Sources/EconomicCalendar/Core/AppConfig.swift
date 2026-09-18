import Foundation

/// Fetch/notification configuration. Replaces the `data_source:` /
/// `filters:` / `notifications:` blocks of the legacy config.yaml.
/// Defaults mirror config.yaml; power users can override individual keys via
/// `defaults write com.economiccalendar.widget config.<key> ...`.
struct AppConfig: Sendable {
    var sourceURL = "https://www.investing.com/economic-calendar/"
    var refreshIntervalMinutes = 10
    var dateRangeDays = 2

    /// Fetch-time currency gate (empty = all currencies).
    var fetchCurrencies: Set<String> = ["USD", "EUR", "GBP", "JPY", "CNY"]
    var fetchMinImportance = Importance.low

    var notificationsEnabled = true
    var leadTimeMinutes = 15
    var notifyMinImportance = Importance.high
    var sound = "default"

    var refreshInterval: Duration { .seconds(max(1, refreshIntervalMinutes) * 60) }

    static func load(ud: UserDefaults = .standard) -> AppConfig {
        var c = AppConfig()
        if let s = ud.string(forKey: "config.sourceURL") { c.sourceURL = s }
        let interval = ud.integer(forKey: "config.refreshIntervalMinutes")
        if interval > 0 { c.refreshIntervalMinutes = interval }
        let range = ud.integer(forKey: "config.dateRangeDays")
        if range > 0 { c.dateRangeDays = range }
        if let list = ud.stringArray(forKey: "config.currencies") { c.fetchCurrencies = Set(list.map { $0.uppercased() }) }
        if let label = ud.string(forKey: "config.minImportance") { c.fetchMinImportance = Importance(label: label) }
        if ud.object(forKey: "config.notificationsEnabled") != nil { c.notificationsEnabled = ud.bool(forKey: "config.notificationsEnabled") }
        let lead = ud.integer(forKey: "config.leadTimeMinutes")
        if lead > 0 { c.leadTimeMinutes = lead }
        if let label = ud.string(forKey: "config.notifyMinImportance") { c.notifyMinImportance = Importance(label: label) }
        if let s = ud.string(forKey: "config.sound") { c.sound = s }
        return c
    }
}

/// One-time import of the legacy Python app's config.yaml (geometry, always on
/// top, filters, fetch/notification settings). Read-only — never renames or
/// writes the YAML so the Python app keeps working side by side.
enum LegacyMigrator {
    static func migrateIfNeeded() {
        guard !AppSettings.didMigrateYAML else { return }
        AppSettings.didMigrateYAML = true
        let url = AppPaths.legacyConfigFile
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let parsed = parseYAMLSubset(text)
        let ud = UserDefaults.standard

        if let g = parsed.geometry {
            AppSettings.geometry = AppSettings.geometryFromQt(
                x: g.x, y: g.y, width: g.width, height: g.height)
        }
        if let aot = parsed.alwaysOnTop { AppSettings.alwaysOnTop = aot }
        if let minImp = parsed.filterMinImportance {
            AppSettings.filterMinImportance = Importance(label: minImp).rawValue
        }
        if let setMinImp = parsed.notifyMinImportance {
            ud.set(setMinImp, forKey: "config.notifyMinImportance")
        }
        if let currencies = parsed.fetchCurrencies, !currencies.isEmpty {
            ud.set(currencies, forKey: "config.currencies")
        }
        if let url2 = parsed.sourceURL { ud.set(url2, forKey: "config.sourceURL") }
        if let interval = parsed.refreshInterval { ud.set(interval, forKey: "config.refreshIntervalMinutes") }
        if let range = parsed.dateRangeDays { ud.set(range, forKey: "config.dateRangeDays") }
        if let lead = parsed.leadTime { ud.set(lead, forKey: "config.leadTimeMinutes") }
        if let enabled = parsed.notificationsEnabled { ud.set(enabled, forKey: "config.notificationsEnabled") }

        AppLog.shared.info("Migrated legacy config.yaml from \(url.path)")
    }

    struct Parsed {
        var geometry: (x: Double, y: Double, width: Double, height: Double)?
        var alwaysOnTop: Bool?
        var filterMinImportance: String?
        var notifyMinImportance: String?
        var fetchCurrencies: [String]?
        var sourceURL: String?
        var refreshInterval: Int?
        var dateRangeDays: Int?
        var leadTime: Int?
        var notificationsEnabled: Bool?
    }

    /// Minimal YAML-subset parser: enough for the flat/nested scalar keys and
    /// one string list the legacy config uses. Not a general YAML parser.
    static func parseYAMLSubset(_ text: String) -> Parsed {
        var p = Parsed()
        var section: String?
        var subsection: String?
        var currencies: [String] = []
        var geometry: [String: Double] = [:]

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = line.count - line.drop(while: { $0 == " " }).count

            if trimmed.hasSuffix(":") {
                let key = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                if indent == 0 {
                    section = key
                    subsection = nil
                } else {
                    subsection = key
                }
                continue
            }

            if trimmed.hasPrefix("- ") {
                let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if section == "filters" && subsection == "currencies" {
                    currencies.append(value.uppercased())
                }
                continue
            }

            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch (section, subsection, key) {
            case ("data_source", nil, "url"):
                p.sourceURL = value
            case ("data_source", nil, "refresh_interval_minutes"):
                p.refreshInterval = Int(value)
            case ("data_source", nil, "date_range_days"):
                p.dateRangeDays = Int(value)
            case ("filters", nil, "min_importance"):
                p.filterMinImportance = value
            case ("notifications", nil, "min_importance"):
                p.notifyMinImportance = value
            case ("notifications", nil, "lead_time_minutes"):
                p.leadTime = Int(value)
            case ("notifications", nil, "enabled"):
                p.notificationsEnabled = value == "true"
            case ("widget", "geometry", "x"):
                geometry["x"] = Double(value)
            case ("widget", "geometry", "y"):
                geometry["y"] = Double(value)
            case ("widget", "geometry", "width"):
                geometry["width"] = Double(value)
            case ("widget", "geometry", "height"):
                geometry["height"] = Double(value)
            case ("widget", nil, "always_on_top"):
                p.alwaysOnTop = value == "true"
            default:
                break
            }
        }

        if geometry.count == 4 {
            p.geometry = (geometry["x"]!, geometry["y"]!, geometry["width"]!, geometry["height"]!)
        }
        if !currencies.isEmpty { p.fetchCurrencies = currencies }
        return p
    }
}
