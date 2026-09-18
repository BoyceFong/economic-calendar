import SwiftUI

/// One calendar row. Port of the Qt EventRowDelegate painting:
/// TIME | CUR | IMP | EVENT | ACTUAL | FORECAST | PREVIOUS.
struct EventRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppActions.self) private var actions

    let data: EventRowData

    @State private var hovering = false

    private var event: EconomicEvent { data.event }

    var body: some View {
        HStack(spacing: 0) {
            timeCell
                .frame(width: Theme.colTime, alignment: .leading)

            currencyCell
                .frame(width: Theme.colCurrency, alignment: .center)

            starsCell
                .frame(width: Theme.colImportance, alignment: .center)

            eventCell
                .frame(maxWidth: .infinity, alignment: .leading)

            valueCell(event.actual, color: actualColor)
                .frame(width: Theme.colActual, alignment: .trailing)

            valueCell(event.forecast, color: nil)
                .frame(width: Theme.colForecast, alignment: .trailing)

            valueCell(event.previous, color: nil)
                .frame(width: Theme.colPrevious, alignment: .trailing)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .frame(minHeight: 40, alignment: .center)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { actions.openInBrowser(event) }
        .overlay {
            // Ctrl+click → copy (parity). The catcher only intercepts the
            // event while ⌃ is held, so plain clicks flow to SwiftUI.
            ControlClickCatcher { actions.copyEventDetails(event) }
        }
        .contextMenu {
            ContextMenuContent(event: event)
        }
    }

    // MARK: Cells

    private var timeCell: some View {
        Text(Theme.hhmm(event.time))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.trailing, 6)
            .help(Theme.tooltipTime(event.time))
    }

    private var currencyCell: some View {
        Text(Theme.flagLabel(event.currency))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .help(event.currency)
    }

    private var starsCell: some View {
        StarsView(level: event.importance)
    }

    private var eventCell: some View {
        Text(event.name)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
            .padding(.trailing, 8)
            .help("\(event.name)\n\(Theme.tooltipTime(event.time)) · \(event.importance.capitalizedLabel)\nActual: \(event.actual ?? "—")  Forecast: \(event.forecast ?? "—")  Previous: \(event.previous ?? "—")")
    }

    private func valueCell(_ text: String?, color: Color?) -> some View {
        Text(text ?? "—")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
            .lineLimit(1)
            .padding(.leading, 4)
    }

    /// Actual beats forecast → green, misses → red (port of the refresh() logic).
    private var actualColor: Color? {
        guard let actual = event.actual, !actual.isEmpty else { return nil }
        guard let av = EventParsing.tryFloat(actual) else { return nil }
        let fv = EventParsing.tryFloat(event.forecast)
        if let fv {
            return av >= fv ? Theme.beatColor : Theme.missColor
        }
        return Theme.beatColor
    }

    // MARK: Background (port of _bg_for_row)

    private var rowBackground: Color {
        let high = event.isHighImpact
        if hovering {
            return high ? Color.red.opacity(0.12) : Color.primary.opacity(0.07)
        }
        if high { return Color.red.opacity(0.06) }
        return data.isAlt ? Color.primary.opacity(0.03) : Color.clear
    }
}
