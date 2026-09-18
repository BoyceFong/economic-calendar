import Foundation

/// Periodic fetch + notification loops. Port of `scheduler.py`:
/// first fetch 3s after launch, then every config interval; notification
/// check every 60s. The overlap guard works because both the guard and the
/// fetcher are MainActor-isolated.
@MainActor
final class RefreshScheduler {
    private let config: AppConfig
    private let fetcher: CalendarFetcher
    private let cache: CacheStore
    private let notifier: Notifier?
    private let model: AppModel
    private let notified: NotifiedStore

    private var isFetching = false
    private var loops: [Task<Void, Never>] = []

    init(config: AppConfig, fetcher: CalendarFetcher, cache: CacheStore,
         notifier: Notifier?, notified: NotifiedStore, model: AppModel) {
        self.config = config
        self.fetcher = fetcher
        self.cache = cache
        self.notifier = notifier
        self.notified = notified
        self.model = model
    }

    func start() {
        Task { await notified.purge(olderThanDays: 30) }

        // Fetch loop: initial fetch after 3s, then every interval (parity).
        loops.append(Task { [config] in
            try? await Task.sleep(for: .seconds(3))
            await self.runFetch()
            while !Task.isCancelled {
                try? await Task.sleep(for: config.refreshInterval)
                await self.runFetch()
            }
        })

        // Notification loop: check every 60 seconds (parity).
        loops.append(Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self.checkNotifications()
            }
        })
        AppLog.shared.info("Scheduler started: fetch every \(config.refreshIntervalMinutes)m, notify every 60s")
    }

    func stop() {
        for loop in loops { loop.cancel() }
        loops.removeAll()
    }

    /// Context menu "Refresh now" (parity with trigger_fetch_now).
    func triggerFetchNow() {
        model.setStatus("Refreshing…")
        AppLog.shared.info("Manual fetch triggered")
        Task { await runFetch() }
    }

    private func runFetch() async {
        guard !isFetching else {
            AppLog.shared.debug("Fetch already running, skipping")
            return
        }
        isFetching = true
        model.setStatus("Fetching latest data...")
        AppLog.shared.info("Starting fetch")

        let result = await fetcher.fetchAndParse()

        if let error = result.errorDescription {
            AppLog.shared.error("Fetch failed: \(error)")
            model.setStatus("Fetch error: \(String(error.prefix(60)))")
        } else if result.events.isEmpty {
            // Empty extract → keep old cache (parity with fetch_and_cache).
            AppLog.shared.info("Fetch returned 0 events, checking cache fallback...")
            if let snapshot = await cache.read(), !snapshot.events.isEmpty {
                AppLog.shared.info("Using \(snapshot.events.count) cached events")
                model.applyFetched(events: snapshot.events, fetchedAt: snapshot.fetchedAt ?? Date())
            } else {
                model.applyFetched(events: [], fetchedAt: Date())
            }
        } else {
            let previous = await cache.read()?.events ?? []
            let events = EventParsing.stabilizeUnscheduledTimes(
                result.events, previous: previous, fallbackURL: config.sourceURL)
            await cache.write(events: events, fetchedAt: Date())
            model.applyFetched(events: events, fetchedAt: Date())
        }

        await checkNotifications()
        isFetching = false
    }

    private func checkNotifications() async {
        await notifier?.checkAndNotify(events: model.allEvents, now: Date())
    }
}
