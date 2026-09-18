import Foundation

/// Resolve data/log paths for bundled (.app) and dev (bare executable) modes.
/// Port of `paths.py`. Same file names as the Python app so cache.json and
/// notified.json carry over in place.
enum AppPaths {
    static let appName = "EconomicCalendar"

    /// True when running inside a proper .app bundle.
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var applicationSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var logsBaseDir: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Logs").appendingPathComponent(appName, isDirectory: true)
    }

    /// Writable data dir: App Support when bundled, ./data in dev (shared with
    /// the legacy Python app when run from the repo root).
    static var dataDirectory: URL {
        let url = isBundled ? applicationSupportDir : URL(fileURLWithPath: "data", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var logDirectory: URL {
        let url = isBundled ? logsBaseDir : dataDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var cacheFile: String { dataDirectory.appendingPathComponent("cache.json").path }
    static var stateFile: String { dataDirectory.appendingPathComponent("notified.json").path }
    static var logFile: String { logDirectory.appendingPathComponent("widget.log").path }

    /// Legacy YAML config written by the Python app. Read-only (one-time migration).
    static var legacyConfigFile: URL {
        isBundled
            ? applicationSupportDir.appendingPathComponent("config.yaml")
            : URL(fileURLWithPath: "config.yaml", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
}
