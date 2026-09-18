import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let fetchOnce: Bool

    private var model: AppModel!
    private var actions: AppActions!
    private var panel: AppPanel!
    private var scheduler: RefreshScheduler!
    private var cache: CacheStore!
    private var notified: NotifiedStore!
    private var notifier: Notifier?

    private var geometrySaveTask: Task<Void, Never>?
    private var transparencyObserver: AnyCancellable?
    private var focusObservers: [NSObjectProtocol] = []
    private var glassBacking: NSGlassEffectView?

    /// Mirror native desktop widgets: readable glass when the desktop itself
    /// is focused or our panel is key; translucent when another app's window
    /// has focus. `didActivateApplication` + panel key notifications drive it.
    private func installFocusObservers() {
        // State is simply "is THIS window focused": readable glass when key,
        // translucent widget-look otherwise.
        let center = NotificationCenter.default
        focusObservers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.model.setPanelFocused(true) })
        focusObservers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.model.setPanelFocused(false) })
    }

    init(fetchOnce: Bool = false) {
        self.fetchOnce = fetchOnce
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyMigrator.migrateIfNeeded()

        var glassMode: GlassMode = switch ProcessInfo.processInfo.environment["EC_GLASS_MODE"] {
        case "material": .material
        case "solid": .solid
        default: .glass
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            glassMode = .solid
        }

        cache = CacheStore(path: AppPaths.cacheFile)
        notified = NotifiedStore(path: AppPaths.stateFile)
        notifier = Notifier(config: AppConfig.load(), store: notified)
        model = AppModel(glassMode: glassMode)
        actions = AppActions(model: model)

        Task { await model.loadFromCache(cache) }

        buildPanel()

        let config = AppConfig.load()
        let fetcher = CalendarFetcher(config: config)
        scheduler = RefreshScheduler(
            config: config, fetcher: fetcher, cache: cache,
            notifier: notifier, notified: notified, model: model)
        actions.attach(panel: panel, scheduler: scheduler)

        observeReduceTransparency()
        installFocusObservers()

        model.onInteractingChange = { [weak self] interacting in
            self?.updateGlassBacking(interacting: interacting)
        }
        updateGlassBacking(interacting: model.isInteracting)

        if fetchOnce {
            Task { await fetchOnceAndExit(config: config) }
        } else {
            scheduler.start()
            Task { await notifier?.requestAuthorizationIfNeeded() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.stop()
        panel?.persistFrame()
        focusObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Window assembly

    private func buildPanel() {
        let panel = AppPanel(
            contentRect: NSRect(x: 0, y: 0, width: AppSettings.geometry.width, height: AppSettings.geometry.height),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = AppPanel.makeAlwaysOnTop(AppSettings.alwaysOnTop)
        panel.delegate = self
        // Clicking the panel makes it key (without activating the app) — the
        // "user tapped the widget → readable glass" signal.
        panel.becomesKeyOnlyIfNeeded = false
        // Manual resize range: wide enough for long event names, never
        // smaller than the fixed columns allow (parity with the Qt minimum).
        panel.minSize = NSSize(width: 524, height: 300)
        panel.maxSize = NSSize(width: 1200, height: 1600)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panel.frame.width, height: panel.frame.height))
        container.autoresizingMask = [.width, .height]

        if model.glassMode == .glass {
            // BOTH card materials live on this single AppKit view — readable
            // (.regular) and translucent (.clear, the native-widget look).
            // Its backdrop sampling stays live across style flips; SwiftUI
            // glassEffect would freeze after being recreated (branch-switch).
            let backing = NSGlassEffectView(frame: container.bounds)
            backing.style = .clear
            backing.cornerRadius = Theme.cornerRadius
            backing.wantsLayer = true
            backing.layer?.masksToBounds = true
            backing.layer?.cornerRadius = Theme.cornerRadius
            backing.autoresizingMask = [.width, .height]
            container.addSubview(backing)
            glassBacking = backing
        }

        if model.glassMode == .material {
            let effect = NSVisualEffectView(frame: container.bounds)
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Theme.cornerRadius
            effect.layer?.masksToBounds = true
            effect.autoresizingMask = [.width, .height]
            container.addSubview(effect)
        }

        let hosting = NSHostingView(
            rootView: RootView()
                .environment(model)
                .environment(actions))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        panel.restoreFrame()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateCardShadow()

        self.panel = panel
    }

    /// Flip the single AppKit glass card backing between materials
    /// (readable `.regular` ↔ translucent widget-style `.clear`).
    /// The style setter resets cornerRadius — re-apply it every flip, or the
    /// glass pokes out past the rounded content as straight-corner dark edges.
    private func updateGlassBacking(interacting: Bool) {
        guard let glassBacking, model.glassMode == .glass else { return }
        glassBacking.style = interacting ? .regular : .clear
        glassBacking.cornerRadius = Theme.cornerRadius
        glassBacking.wantsLayer = true
        glassBacking.layer?.masksToBounds = true
        glassBacking.layer?.cornerRadius = Theme.cornerRadius
    }

    private func observeReduceTransparency() {
        transparencyObserver = NSWorkspace.shared.publisher(
            for: \.accessibilityDisplayShouldReduceTransparency)
            .sink { [weak self] reduced in
                Task { @MainActor in
                    guard let self else { return }
                    if reduced {
                        self.model.glassMode = .solid
                    } else if ProcessInfo.processInfo.environment["EC_GLASS_MODE"] == nil {
                        self.model.glassMode = .glass
                    }
                }
            }
    }

    // MARK: - CLI helper (--fetch-once)

    private func fetchOnceAndExit(config: AppConfig) async {
        let fetcher = CalendarFetcher(config: config)
        let result = await fetcher.fetchAndParse()
        if !result.events.isEmpty {
            await cache.write(events: result.events, fetchedAt: Date())
        }
        let events = result.events.isEmpty
            ? (await cache.read()?.events ?? [])
            : result.events
        PrintCacheTool.printTable(events)
        exit(0)
    }
}

// MARK: - NSWindowDelegate (geometry persistence, borderless shadow upkeep)

extension AppDelegate: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        panel?.invalidateCardShadow()
        geometrySaveTask?.cancel()
        geometrySaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            panel?.persistFrame()
        }
    }

    func windowDidResize(_ notification: Notification) {
        panel?.invalidateCardShadow()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        panel?.invalidateCardShadow()
        panel?.persistFrame()
    }
}
