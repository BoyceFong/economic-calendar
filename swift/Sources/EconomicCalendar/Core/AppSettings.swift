import AppKit
import Foundation

/// App-level persisted settings (window geometry, always-on-top, UI filters).
/// Replaces the `widget:` block of the legacy config.yaml.
enum AppSettings {
    private static var ud: UserDefaults { .standard }

    // MARK: Geometry (macOS top-left coordinates)

    static var geometry: CGRect {
        get {
            let d = ud.dictionary(forKey: "geometry") as? [String: Double] ?? [:]
            return CGRect(
                x: d["x"] ?? 0,
                y: d["y"] ?? 0,
                width: d["width"] ?? 578,
                height: d["height"] ?? 705
            )
        }
        set {
            ud.set(["x": newValue.origin.x, "y": newValue.origin.y,
                    "width": newValue.width, "height": newValue.height],
                   forKey: "geometry")
        }
    }

    // MARK: Window behavior

    static var alwaysOnTop: Bool {
        get { ud.bool(forKey: "alwaysOnTop") }
        set { ud.set(newValue, forKey: "alwaysOnTop") }
    }

    // MARK: UI filters (persisted; empty currency set = all)

    static var filterMinImportance: Int {
        get { ud.integer(forKey: "filter.minImportance") == 0 ? 1 : ud.integer(forKey: "filter.minImportance") }
        set { ud.set(newValue, forKey: "filter.minImportance") }
    }

    static var filterCurrencies: [String] {
        get { ud.stringArray(forKey: "filter.currencies") ?? [] }
        set { ud.set(newValue.sorted(), forKey: "filter.currencies") }
    }

    // MARK: Misc

    static var notificationAuthRequested: Bool {
        get { ud.bool(forKey: "notification.authRequested") }
        set { ud.set(newValue, forKey: "notification.authRequested") }
    }

    static var didMigrateYAML: Bool {
        get { ud.bool(forKey: "migration.didMigrateYAML") }
        set { ud.set(newValue, forKey: "migration.didMigrateYAML") }
    }

    /// Qt top-left (y measured from screen top) → macOS top-left (y from bottom).
    static func geometryFromQt(x: Double, y: Double, width: Double, height: Double) -> CGRect {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 900
        return CGRect(x: x, y: primaryMaxY - y, width: width, height: height)
    }
}
