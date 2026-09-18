import SwiftUI

/// One calendar row. Port of the Qt EventRowDelegate painting:
/// TIME | CUR | IMP | EVENT | ACTUAL | FORECAST | PREVIOUS.
struct EventRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppActions.self) private var actions
    @Environment(\.widgetIdle) private var widgetIdle

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
                .fill(widgetIdle ? IdlePalette.hairline : Color.primary.opacity(0.08))
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
        Text(event.timeText)
            .font(.system(size: 12))
            .foregroundStyle(widgetIdle ? IdlePalette.secondary : Color.secondary)
            .lineLimit(1)
            .padding(.trailing, 6)
            .help(event.timeLabel == nil
                  ? Theme.tooltipTime(event.time)
                  : "\(event.timeLabel!) · \(Theme.tooltipTime(event.time))")
    }

    private var currencyCell: some View {
        Text(Theme.flagLabel(event.currency))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(widgetIdle ? IdlePalette.primary : Color.primary)
            // Flag emoji can't be recolored, so the idle card desaturates it —
            // the only way to keep a strict black/white/gray palette.
            .grayscale(widgetIdle ? 1 : 0)
            .lineLimit(1)
            .help(event.currency)
    }

    private var starsCell: some View {
        StarsView(level: event.importance)
    }

    private var eventCell: some View {
        Text(event.name)
            .font(.system(size: 12))
            .foregroundStyle(widgetIdle ? IdlePalette.primary : Color.primary)
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
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(
                widgetIdle ? IdlePalette.tertiary : Color(nsColor: .tertiaryLabelColor)))
            .lineLimit(1)
            .padding(.leading, 4)
    }

    /// Actual beats forecast → green, misses → red (port of the refresh()
    /// logic); in the monochrome idle card the same distinction rides on
    /// brightness instead of hue.
    private var actualColor: Color? {
        guard let actual = event.actual, !actual.isEmpty else { return nil }
        guard let av = EventParsing.tryFloat(actual) else { return nil }
        let fv = EventParsing.tryFloat(event.forecast)
        if let fv {
            return av >= fv
                ? (widgetIdle ? IdlePalette.beat : Theme.beatColor)
                : (widgetIdle ? IdlePalette.miss : Theme.missColor)
        }
        return widgetIdle ? IdlePalette.beat : Theme.beatColor
    }

    // MARK: Background (port of _bg_for_row)

    private var rowBackground: Color {
        let high = event.isHighImpact
        if hovering {
            if widgetIdle { return high ? IdlePalette.highImpactHover : IdlePalette.rowFill }
            return high ? Color.red.opacity(0.12) : Color.primary.opacity(0.07)
        }
        if high { return widgetIdle ? IdlePalette.highImpactFill : Color.red.opacity(0.06) }
        guard data.isAlt else { return Color.clear }
        return widgetIdle ? IdlePalette.rowFill : Color.primary.opacity(0.03)
    }
}
