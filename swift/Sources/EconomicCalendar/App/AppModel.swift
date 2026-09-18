import AppKit
import Foundation
import Observation
import SwiftUI

enum GlassMode: Sendable {
    case glass       // SwiftUI .glassEffect (macOS 26 Liquid Glass)
    case material    // AppKit NSVisualEffectView fallback (EC_GLASS_MODE=material)
    case solid       // opaque card (Reduce Transparency)
}

/// Single source of truth for the UI. Port of the state kept in
/// `widget.EconomicCalendarWidget` plus the new filter bar state.
@MainActor
@Observable
final class AppModel {
    // Data (fetch-time filtered, sorted ascending)
    private(set) var allEvents: [EconomicEvent] = []
    private(set) var fetchedAt: Date?

    // UI filters (user-facing; persisted)
    var minImportance: Importance {
        didSet { AppSettings.filterMinImportance = minImportance.rawValue; rebuild(scroll: true, reason: .filter) }
    }
    var selectedCurrencies: Set<String> {
        didSet { AppSettings.filterCurrencies = Array(selectedCurrencies); rebuild(scroll: true, reason: .filter) }
    }

    // Derived display state
    private(set) var displayRows: [DisplayRow] = []
    private(set) var titleCount = ""
    private(set) var status = "Initializing…"

    // Bumped whenever the list should re-scroll to the now divider
    // (initial load, refresh, filter change — never on the idle now-tick).
    private(set) var scrollToken = 0
    private(set) var scrollReason: ScrollReason = .initial

    /// Why the list wants to scroll — lets the view ignore background
    /// refreshes while the user is manually browsing.
    enum ScrollReason: Sendable {
        case initial
        case filter
        case refresh
    }

    var glassMode: GlassMode

    /// Readable `.regular` glass while THIS window is focused (key); the
    /// translucent native-widget `.clear` look in every other case. Simple as
    /// that — no desktop-focus heuristics.
    @ObservationIgnored private var panelFocused = false
    private(set) var isInteracting = false

    var isIdle: Bool { !isInteracting }

    /// Notified on every readable↔translucent switch; the AppKit layer uses
    /// it to flip the NSGlassEffectView card material.
    @ObservationIgnored var onInteractingChange: ((Bool) -> Void)?

    func setPanelFocused(_ on: Bool) {
        guard panelFocused != on else { return }
        panelFocused = on
        withAnimation(.easeInOut(duration: 0.35)) {
            isInteracting = on
        }
        onInteractingChange?(on)
    }

    private var flashTask: Task<Void, Never>?
    private var nowTickTask: Task<Void, Never>?

    init(glassMode: GlassMode) {
        self.glassMode = glassMode
        self.minImportance = Importance(rawValue: AppSettings.filterMinImportance) ?? .low
        self.selectedCurrencies = Set(AppSettings.filterCurrencies)
        startNowTick()
    }

    // MARK: - Data flow

    func loadFromCache(_ cache: CacheStore) async {
        guard let snapshot = await cache.read(), !snapshot.events.isEmpty else {
            status = "Waiting for data — fetching…"
            rebuild(scroll: false, reason: .initial)
            return
        }
        applyFetched(events: snapshot.events, fetchedAt: snapshot.fetchedAt ?? Date(), reason: .initial)
    }

    func applyFetched(events: [EconomicEvent], fetchedAt: Date, reason: ScrollReason = .refresh) {
        // Ordering invariant: the list and cache are ALWAYS time-sorted,
        // regardless of what upstream produced.
        allEvents = events.sorted { $0.time < $1.time }
        self.fetchedAt = fetchedAt
        rebuild(scroll: true, reason: reason)
    }

    /// Currencies present in the cached dataset (drives the filter popover).
    var availableCurrencies: [String] {
        Set(allEvents.map(\.currency)).sorted()
    }

    var visibleEvents: [EconomicEvent] {
        allEvents.filter { event in
            (selectedCurrencies.isEmpty || selectedCurrencies.contains(event.currency))
                && event.importance >= minImportance
        }
    }

    // MARK: - Display rebuild

    private func rebuild(scroll: Bool, reason: ScrollReason) {
        let visible = visibleEvents
        displayRows = DisplayRow.buildRows(events: visible, now: Date())
        titleCount = visible.isEmpty ? "No events" : "\(visible.count) events"
        if visible.isEmpty {
            // Parity with the Qt app: empty list (no data yet, or filters
            // removed everything) shows the waiting status line.
            status = "Waiting for data — fetching…"
        } else {
            status = baselineStatus
        }
        if scroll && !visible.isEmpty {
            scrollReason = reason
            scrollToken += 1
        }
    }

    private var baselineStatus: String {
        if allEvents.isEmpty { return "Waiting for data — fetching…" }
        let count = visibleEvents.count
        if let fetchedAt {
            return "Updated \(Theme.hhmm(fetchedAt)) · \(count) events"
        }
        return "\(count) events"
    }

    /// Transient status feedback ("Copied: …", "Always on Top: On", …).
    /// The old app let the next refresh cycle overwrite it; we restore the
    /// baseline after a few seconds — same visible effect.
    func setStatus(_ text: String) {
        flashTask?.cancel()
        status = text
    }

    func flashStatus(_ text: String) {
        flashTask?.cancel()
        status = text
        flashTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            status = baselineStatus
        }
    }

    // MARK: - Now tick (30s, parity with _now_timer)

    private func startNowTick() {
        nowTickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                // Re-insert the divider at its new boundary (no auto-scroll —
                // never yank the list while the user is reading).
                displayRows = DisplayRow.buildRows(events: visibleEvents, now: Date())
            }
        }
    }
}
