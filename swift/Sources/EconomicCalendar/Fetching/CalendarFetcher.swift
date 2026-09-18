import AppKit
import Foundation
import WebKit

/// Offscreen WKWebView pipeline replacing the old Playwright headless-Chromium
/// scraper. Loads the investing.com calendar page, dismisses cookie dialogs,
/// and runs the same in-page extraction JS (Resources/ExtractCalendar.js).
///
/// WKWebView must live on the main actor; waiting is done with cooperative
/// Task.sleep polling so the UI thread is never blocked.
@MainActor
final class CalendarFetcher: NSObject {
    enum FetchError: Error, CustomStringConvertible {
        case timeout(String)
        case invalidResponse

        var description: String {
            switch self {
            case .timeout(let what): "timeout waiting for \(what)"
            case .invalidResponse: "invalid response from page"
            }
        }
    }

    struct Result: Sendable {
        let events: [EconomicEvent]
        /// Non-nil when the pipeline threw (page never loaded etc.). An empty
        /// extract is NOT an error — the caller falls back to cache (parity).
        let errorDescription: String?
    }

    private let config: AppConfig
    private var webView: WKWebView?
    private var offscreenWindow: NSWindow?
    private var failureBox: OnceResultBox<Error>?
    private var activityToken: NSObjectProtocol?

    private lazy var extractJS: String = {
        guard let url = Bundle.module.url(forResource: "ExtractCalendar", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            AppLog.shared.error("ExtractCalendar.js missing from bundle")
            return "() => []"
        }
        return source
    }()

    init(config: AppConfig) {
        self.config = config
    }

    // MARK: - Pipeline

    func fetchAndParse() async -> Result {
        beginActivity()
        defer { endActivity() }

        do {
            let webView = try await ensureWebView()

            AppLog.shared.info("Navigating to \(config.sourceURL) ...")
            try await loadPage(webView, urlString: config.sourceURL)
            try await waitForTable(webView, budget: 60)
            try await dismissCookieDialogs(webView)
            // Settle wait — WKWebView has no networkidle equivalent; a fixed
            // grace period plus the table poll covers late hydration.
            try await Task.sleep(for: .seconds(5))

            var rawRows = try await extractRows(webView)
            AppLog.shared.info("Extracted \(rawRows.count) raw rows")
            // EC_DEBUG_ROWS=1 → dump every raw row (field forensics).
            let dumpAll = ProcessInfo.processInfo.environment["EC_DEBUG_ROWS"] == "1"
            for (i, r) in (dumpAll ? Array(rawRows.enumerated()) : Array(rawRows.prefix(5).enumerated())) {
                AppLog.shared.debug("Row \(i): date='\(r.date)' time='\(r.time)' cc='\(r.countryCode)' bull=\(r.bull) name='\(r.name)'")
            }

            // Retry ladder for hidden-page throttling: spoof visibilityState,
            // then attach the webview to a real (offscreen) window.
            if rawRows.isEmpty {
                AppLog.shared.info("Empty extract; retrying with visibility spoof")
                _ = try? await evaluate(
                    webView,
                    "Object.defineProperty(document,'visibilityState',{get:()=>'visible'})")
                try await Task.sleep(for: .seconds(3))
                rawRows = (try? await extractRows(webView)) ?? []
            }
            if rawRows.isEmpty {
                AppLog.shared.info("Still empty; attaching webview to offscreen window")
                attachOffscreenWindow(webView)
                try await Task.sleep(for: .seconds(3))
                rawRows = (try? await extractRows(webView)) ?? []
            }

            let events = EventParsing.parseRawRows(
                rawRows,
                fallbackURL: config.sourceURL,
                currencies: config.fetchCurrencies,
                minImportance: config.fetchMinImportance,
                now: Date(),
                dateRangeDays: config.dateRangeDays)
            AppLog.shared.info("Parsed \(events.count) valid events")

            if events.isEmpty {
                await dumpDebugHTML(webView)
            }
            return Result(events: events, errorDescription: nil)
        } catch {
            AppLog.shared.error("Fetch error: \(error)")
            return Result(events: [], errorDescription: error.localizedDescription)
        }
    }

    // MARK: - Steps

    /// Kick off navigation. Unlike Playwright's domcontentloaded wait, WKWebView's
    /// didFinish delegate never fires reliably on ad-heavy pages, so success is
    /// detected by polling for the table (waitForTable); only hard failures are
    /// gated here.
    private func loadPage(_ webView: WKWebView, urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw FetchError.invalidResponse
        }
        failureBox = OnceResultBox<Error>()
        webView.load(URLRequest(url: url))
    }

    private func waitForTable(_ webView: WKWebView, budget: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(budget)
        while Date() < deadline {
            if let failure = failureBox?.take() {
                _ = try failure.get()
            }
            let present = (try? await evaluate(
                webView,
                "JSON.stringify(!!document.querySelector(\"table[class*='datatable-v2']\"))")) == "true"
            if present {
                AppLog.shared.info("datatable-v2 found")
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        // Old app: wait_for_selector miss → fall through to extraction anyway.
        AppLog.shared.info("datatable-v2 not found after \(Int(budget))s, continuing")
    }

    private func dismissCookieDialogs(_ webView: WKWebView) async throws {
        let script = """
        (() => {
            const sels = [
                "#onetrust-accept-btn-handler",
                "button[data-testid='uc-accept-all-button']",
                "button.didomi-continue-without-agreeing",
                "#sp-accept-all",
            ];
            const clicked = [];
            for (const s of sels) {
                try {
                    const el = document.querySelector(s);
                    if (el && el.offsetParent !== null) { el.click(); clicked.push(s); }
                } catch (e) {}
            }
            return JSON.stringify(clicked);
        })()
        """
        if let clicked = try? await evaluate(webView, script), clicked != "[]" {
            AppLog.shared.info("Dismissed dialogs: \(clicked)")
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    private func extractRows(_ webView: WKWebView) async throws -> [RawRow] {
        let json = try await evaluate(
            webView, "JSON.stringify((\(extractJS))())", timeout: 30)
        guard let data = json.data(using: .utf8) else { throw FetchError.invalidResponse }
        return (try? JSONDecoder().decode([RawRow].self, from: data)) ?? []
    }

    private func dumpDebugHTML(_ webView: WKWebView) async {
        guard let html = try? await evaluate(webView, "document.documentElement.outerHTML", timeout: 10) else { return }
        let url = URL(fileURLWithPath: AppPaths.dataDirectory.appendingPathComponent("debug_page.html").path)
        try? html.data(using: .utf8)?.write(to: url)
        AppLog.shared.info("Saved debug HTML: \(url.path)")
    }

    // MARK: - WebView management

    private func ensureWebView() async throws -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        // Persist cookies across fetches — a warm Cloudflare clearance means
        // fewer challenges than Playwright's throwaway contexts.
        configuration.websiteDataStore = .default()
        if let ruleList = try? await Self.compileMediaBlocker() {
            configuration.userContentController.add(ruleList)
        }
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900), configuration: configuration)
        wv.navigationDelegate = self
        webView = wv
        return wv
    }

    /// Block images/media — native equivalent of Playwright's route.abort.
    private static func compileMediaBlocker() async throws -> WKContentRuleList {
        let json = """
        {"trigger":{"url-filter":".*","resource-type":["image","media"]},"action":{"type":"block"}}
        """
        guard let store = WKContentRuleListStore.default() else {
            throw FetchError.invalidResponse
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: "block-media", encodedContentRuleList: json) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: error ?? FetchError.invalidResponse)
                }
            }
        }
    }

    /// Last-resort fallback: some pages throttle JS timers when the webview has
    /// never been in a window; a real window placed far offscreen fixes it.
    private func attachOffscreenWindow(_ webView: WKWebView) {
        guard offscreenWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 12000, y: 0, width: 1440, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFrontRegardless()
        offscreenWindow = window
    }

    // MARK: - App Nap protection (the old fetch ran in a daemon thread)

    private func beginActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Fetching economic calendar")
    }

    private func endActivity() {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    // MARK: - JS evaluation with timeout (poll-based; no continuation leaks)

    private func evaluate(_ webView: WKWebView, _ script: String, timeout: TimeInterval = 15) async throws -> String {
        let box = OnceResultBox<String>()
        Task {
            do {
                let result = try await webView.evaluateJavaScript(script)
                if let s = result as? String {
                    box.set(s)
                } else if let any = result {
                    box.set(String(describing: any))
                } else {
                    box.set(throwing: FetchError.invalidResponse)
                }
            } catch {
                box.set(throwing: error)
            }
        }
        return try await boxWait(box, what: "JS evaluation", timeout: timeout)
    }

    private func boxWait<T: Sendable>(_ box: OnceResultBox<T>, what: String, timeout: TimeInterval) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = box.take() {
                return try result.get()
            }
            try await Task.sleep(for: .milliseconds(120))
        }
        throw FetchError.timeout(what)
    }
}

// MARK: - Navigation delegate

extension CalendarFetcher: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.failureBox?.set(throwing: error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.failureBox?.set(throwing: error) }
    }
}

/// Thread-safe one-shot result slot; lets completion callbacks (main queue)
/// hand values to an async poller without continuations that can leak.
final class OnceResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func set(_ value: Value) { set(result: .success(value)) }
    func set(throwing error: Error) { set(result: .failure(error)) }

    func set(result: Result<Value, Error>) {
        lock.lock()
        if self.result == nil { self.result = result }
        lock.unlock()
    }

    /// Atomically pop the result, if one has arrived.
    func take() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
