import SwiftUI

/// Right-click menu — port of the Qt context menu:
/// per-event copy/open + currency/min-importance filters + refresh,
/// always-on-top, launch-at-login, quit.
struct ContextMenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(AppActions.self) private var actions

    /// Non-nil when opened over an event row.
    let event: EconomicEvent?

    var body: some View {
        if let event {
            Text(String(event.name.prefix(55)))
                .foregroundStyle(.secondary)
            Divider()
            Button("Copy event details") { actions.copyEventDetails(event) }
            Button("Open in browser") { actions.openInBrowser(event) }
            Divider()
        }

        Menu("Filter by currency") {
            ForEach(model.availableCurrencies, id: \.self) { currency in
                Toggle(currency, isOn: Binding(
                    get: { model.selectedCurrencies.contains(currency) },
                    set: { on in
                        if on { model.selectedCurrencies.insert(currency) }
                        else { model.selectedCurrencies.remove(currency) }
                    }))
            }
            if !model.selectedCurrencies.isEmpty {
                Divider()
                Button("Clear filter") { model.selectedCurrencies = [] }
            }
        }

        Menu("Min importance") {
            ForEach(Importance.allCases.reversed(), id: \.self) { level in
                Toggle(level.capitalizedLabel, isOn: Binding(
                    get: { model.minImportance == level },
                    set: { _ in model.minImportance = level }))
            }
        }

        Divider()
        Button("Refresh now") { actions.refreshNow() }
        Button("Always on Top: \(AppSettings.alwaysOnTop ? "On" : "Off")") { actions.toggleAlwaysOnTop() }
        Divider()
        Button("Launch at Login: \(LoginItemService.isEnabled() ? "On" : "Off")") { actions.toggleLaunchAtLogin() }
        Divider()
        Button("Quit") { actions.quit() }
    }
}
