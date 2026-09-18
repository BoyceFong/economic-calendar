import SwiftUI

/// The scrollable event list with the now-divider as an inserted element.
/// A plain (non-lazy) VStack keeps every height eager, so ScrollViewReader
/// scrollTo lands exactly — auto-scroll is the "jump to current time" feature.
struct EventListView: View {
    let rows: [DisplayRow]
    let scrollToken: Int
    let scrollReason: AppModel.ScrollReason

    /// Last time the user scrolled the list by hand; nil = no active
    /// browsing session (initial state, or already returned to now).
    @State private var lastUserScroll: Date?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                            .id(row.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .onScrollPhaseChange { _, newPhase in
                // Only user-driven phases count; programmatic scrolls animate
                // without touching this.
                switch newPhase {
                case .tracking, .interacting, .decelerating:
                    lastUserScroll = Date()
                default:
                    break
                }
            }
            .onChange(of: scrollToken, initial: true) { _, _ in
                handleScrollRequest(proxy)
            }
            .task {
                await idleReturnLoop(proxy)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: DisplayRow) -> some View {
        switch row {
        case .event(let data):
            EventRowView(data: data)
        case .nowDivider:
            NowDividerView(position: DisplayRow.dividerPosition(in: rows) ?? .middle)
        }
    }

    /// Auto-scroll on load / filter change always; a background refresh must
    /// not yank the list while the user is browsing — the idle timer below
    /// returns it to now instead.
    private func handleScrollRequest(_ proxy: ScrollViewProxy) {
        if scrollReason == .refresh, let last = lastUserScroll,
           Date().timeIntervalSince(last) < Self.idleReturnInterval {
            return
        }
        scrollToDivider(proxy)
    }

    /// After a manual scroll, return to the now-divider once the user has
    /// been idle for 5 minutes.
    private func idleReturnLoop(_ proxy: ScrollViewProxy) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard let last = lastUserScroll else { continue }
            if Date().timeIntervalSince(last) >= Self.idleReturnInterval {
                lastUserScroll = nil
                scrollToDivider(proxy)
            }
        }
    }

    private static let idleReturnInterval: TimeInterval = 5 * 60

    /// Anchor choice per divider position:
    ///   above all → pin divider at the top; below all → bottom;
    ///   middle     → center it. One runloop tick so layout resolves first.
    private func scrollToDivider(_ proxy: ScrollViewProxy) {
        guard !rows.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard let position = DisplayRow.dividerPosition(in: rows) else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                switch position {
                case .aboveAll:
                    proxy.scrollTo(DisplayRow.dividerID, anchor: .top)
                case .belowAll:
                    proxy.scrollTo(DisplayRow.dividerID, anchor: .bottom)
                case .middle:
                    proxy.scrollTo(DisplayRow.dividerID, anchor: .center)
                }
            }
        }
    }
}
