import AppKit
import Foundation

/// User actions shared between row gestures, context menus, and the UI layer.
/// Port of the widget's action methods (_copy, _open_browser, _toggle_aot…).
@MainActor
@Observable
final class AppActions {
    private unowned let model: AppModel
    private weak var panel: AppPanel?
    private weak var scheduler: RefreshScheduler?

    init(model: AppModel) {
        self.model = model
    }

    func attach(panel: AppPanel, scheduler: RefreshScheduler) {
        self.panel = panel
        self.scheduler = scheduler
    }

    /// "{HH:MM} | {flag} | {name}\nActual: … | Forecast: … | Previous: …"
    func copyEventDetails(_ event: EconomicEvent) {
        let text = """
        \(event.timeText) | \(Theme.flagLabel(event.currency)) | \(event.name)
        Actual: \(event.actual ?? "—") | Forecast: \(event.forecast ?? "—") | Previous: \(event.previous ?? "—")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.flashStatus("Copied: \(String(event.name.prefix(45)))")
    }

    func openInBrowser(_ event: EconomicEvent) {
        let urlString = event.sourceURL.isEmpty ? "https://www.investing.com/economic-calendar/" : event.sourceURL
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        model.flashStatus("Opened in browser")
    }

    func refreshNow() {
        scheduler?.triggerFetchNow()
    }

    func toggleAlwaysOnTop() {
        let on = panel?.toggleAlwaysOnTop() ?? AppSettings.alwaysOnTop
        AppSettings.alwaysOnTop = on
        model.flashStatus("Always on Top: \(on ? "On" : "Off")")
    }

    func toggleLaunchAtLogin() {
        let on = LoginItemService.toggle()
        model.flashStatus("Launch at Login: \(on ? "On" : "Off")")
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
