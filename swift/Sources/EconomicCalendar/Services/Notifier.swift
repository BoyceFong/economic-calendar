import AppKit
import Foundation
import UserNotifications

/// Advance-notification dispatcher using the native UN framework (replaces
/// terminal-notifier). Dedup via NotifiedStore — same notified.json as before,
/// so events already announced by the Python app don't re-fire after upgrade.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let config: AppConfig
    private let store: NotifiedStore
    private let center: UNUserNotificationCenter?

    /// UNUserNotificationCenter crashes when the app has no bundle id, so it's
    /// only used for proper .app runs (bare `swift run` degrades to log-only).
    init(config: AppConfig, store: NotifiedStore) {
        self.config = config
        self.store = store
        if config.notificationsEnabled && Bundle.main.bundleIdentifier != nil {
            self.center = UNUserNotificationCenter.current()
        } else {
            self.center = nil
        }
        super.init()
        center?.delegate = self
    }

    /// Ask once, on first bundled launch; denial degrades silently.
    func requestAuthorizationIfNeeded() async {
        guard let center else { return }
        guard !AppSettings.notificationAuthRequested else { return }
        AppSettings.notificationAuthRequested = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Fire notifications for events starting within the lead window.
    /// Port of `notifier.NotificationDispatcher.check_and_notify`.
    func checkAndNotify(events: [EconomicEvent], now: Date) async {
        guard let center else { return }
        let lead = TimeInterval(config.leadTimeMinutes * 60)
        for event in events where event.importance >= config.notifyMinImportance {
            // "All Day" / "Tentative" events carry no reliable instant —
            // notifying against their day-midnight placeholder would misfire.
            guard event.timeLabel == nil else { continue }
            let delta = event.time.timeIntervalSince(now)
            guard delta >= 0, delta <= lead else { continue }
            guard !(await store.isNotified(event.id)) else { continue }

            let minutesLeft = max(1, Int((delta / 60).rounded()))
            var parts = ["Starts in \(minutesLeft) min"]
            if let forecast = event.forecast, !forecast.isEmpty { parts.append("Forecast: \(forecast)") }
            if let previous = event.previous, !previous.isEmpty { parts.append("Previous: \(previous)") }

            let content = UNMutableNotificationContent()
            content.title = "Economic Event: \(event.currency) \(event.name)"
            content.body = parts.joined(separator: " — ")
            content.sound = .default
            content.threadIdentifier = event.id
            content.userInfo = ["source_url": event.sourceURL]

            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
            do {
                try await center.add(request)
                await store.markNotified(event.id, at: now)
                AppLog.shared.info("Notification sent: \(event.currency) \(event.name) (\(minutesLeft)m)")
            } catch {
                AppLog.shared.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate (called on arbitrary queues)

    /// Required for accessory (LSUIElement) apps — banners are suppressed
    /// while the app is active unless willPresent opts in.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Clicking the notification opens the event's investing.com page.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let urlString = response.notification.request.content.userInfo["source_url"] as? String,
              let url = URL(string: urlString) else { return }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }
}
