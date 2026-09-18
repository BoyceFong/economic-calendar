import Foundation
import ServiceManagement

/// Launch-at-login management. Primary: modern SMAppService (System Settings →
/// General → Login Items). Fallback: the osascript System Events flow the
/// Python app used (autostart.py), which also works with ad-hoc signing.
enum LoginItemService {
    private static let appName = "EconomicCalendar"

    static func isEnabled() -> Bool {
        if AppPaths.isBundled {
            if SMAppService.mainApp.status == .enabled { return true }
        }
        return osascriptIsEnabled()
    }

    /// Toggle; returns the new state.
    @discardableResult
    static func toggle() -> Bool {
        if isEnabled() {
            disable()
        } else {
            enable()
        }
        return isEnabled()
    }

    private static func enable() {
        if AppPaths.isBundled {
            do {
                try SMAppService.mainApp.register()
                return
            } catch {
                AppLog.shared.error("SMAppService register failed: \(error.localizedDescription)")
            }
        }
        _ = osascriptEnable()
    }

    private static func disable() {
        if AppPaths.isBundled {
            do {
                try SMAppService.mainApp.unregister()
                return
            } catch {
                AppLog.shared.error("SMAppService unregister failed: \(error.localizedDescription)")
            }
        }
        _ = osascriptDisable()
    }

    // MARK: - osascript fallback (port of autostart.py)

    private static func appBundlePath() -> String? {
        guard AppPaths.isBundled else { return nil }
        return Bundle.main.bundleURL.path
    }

    private static func runOSA(_ script: String) -> (code: Int32, stdout: String, stderr: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, stdout, stderr)
        } catch {
            AppLog.shared.error("osascript failed to launch: \(error.localizedDescription)")
            return nil
        }
    }

    private static func osascriptIsEnabled() -> Bool {
        guard let result = runOSA("tell application \"System Events\" to get the name of every login item"),
              result.code == 0 else {
            AppLog.shared.debug("Login items check unavailable (automation permission denied?)")
            return false
        }
        let names = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return names.contains(appName)
    }

    private static func osascriptEnable() -> Bool {
        guard let appPath = appBundlePath() else {
            AppLog.shared.debug("Auto-start only works for bundled runs")
            return false
        }
        _ = osascriptDisable()
        guard let result = runOSA(
            "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", hidden:false}"
        ) else { return false }
        if result.code == 0 { return true }
        AppLog.shared.error("osascript error: \(result.stderr)")
        return false
    }

    private static func osascriptDisable() -> Bool {
        guard appBundlePath() != nil else { return false }
        guard let result = runOSA(
            "tell application \"System Events\" to delete login item \"\(appName)\""
        ) else { return false }
        if result.code == 0 { return true }
        let notFound = result.stderr.contains("not exist") || result.stderr.contains("Can't get")
        return notFound
    }

}
