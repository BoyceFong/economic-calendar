import SwiftUI

/// Current-time divider — investing.com style: a full-width hairline drawn
/// exactly at the boundary between two event rows, with the Liquid Glass time
/// pill overlapping the two adjacent rows. The divider element itself takes
/// ZERO layout space (`frame(height: 0)`), so rows sit flush like the site.
///
/// Edge cases: when `now` is before/after all events the pill would poke
/// outside the list, so it is drawn entirely below/above the line instead —
/// the divider stays fully visible at the top/bottom of the list.
struct NowDividerView: View {
    let position: DisplayRow.Position

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let label = Theme.hhmm(context.date)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 1.5)
                    .offset(y: lineOffset)

                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(Color.accentColor), in: .capsule)
                    .padding(.leading, 6)
                    .offset(y: pillOffset)
            }
            .frame(height: 0)
            .frame(maxWidth: .infinity)
        }
    }

    /// Nudge the line just inside the list when pinned at an edge so even the
    /// half-pixel against the scroll clip stays visible.
    private var lineOffset: CGFloat {
        switch position {
        case .aboveAll: 1
        case .belowAll: -1
        case .middle: 0
        }
    }

    private var pillOffset: CGFloat {
        switch position {
        case .aboveAll: 10.5
        case .belowAll: -10.5
        case .middle: 0
        }
    }
}
