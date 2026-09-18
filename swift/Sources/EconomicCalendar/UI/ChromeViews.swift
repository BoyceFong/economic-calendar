import SwiftUI

/// Title row: name + event count, with the window drag region behind it.
struct TitleBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.widgetIdle) private var widgetIdle

    var body: some View {
        HStack(spacing: 8) {
            Text("Economic Calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(widgetIdle ? Color.white : Color.primary)
            Spacer()
            Text(model.titleCount)
                .font(.system(size: 13))
                .foregroundStyle(widgetIdle ? Color.white.opacity(0.65) : Color.secondary)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .frame(height: Theme.titleBarHeight)
        .background(DragRegionView())
    }
}

/// Bottom status line — same texts as the Qt status bar.
struct StatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.widgetIdle) private var widgetIdle

    var body: some View {
        HStack(spacing: 0) {
            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(widgetIdle ? Color.white.opacity(0.65) : Color.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .frame(height: Theme.statusHeight)
    }
}

/// Column header row — port of the Qt table header labels. Frames and inner
/// paddings mirror EventRowView's cells exactly so labels align with content.
struct ColumnHeaderView: View {
    @Environment(\.widgetIdle) private var widgetIdle

    var body: some View {
        HStack(spacing: 0) {
            headerLabel("TIME", width: Theme.colTime, alignment: .leading)
                .padding(.trailing, 6)
            headerLabel("CUR", width: Theme.colCurrency, alignment: .center)
            headerLabel("IMP", width: Theme.colImportance, alignment: .center)
            headerLabel("EVENT")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
            headerLabel("ACTUAL", width: Theme.colActual, alignment: .trailing)
                .padding(.leading, 4)
            headerLabel("FORECAST", width: Theme.colForecast, alignment: .trailing)
            headerLabel("PREVIOUS", width: Theme.colPrevious, alignment: .trailing)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .frame(height: Theme.headerHeight)
    }

    @ViewBuilder
    private func headerLabel(_ title: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(widgetIdle ? Color.white.opacity(0.6) : Color.secondary)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

/// Centered italic placeholder — port of the Qt empty state.
struct WaitingView: View {
    @Environment(\.widgetIdle) private var widgetIdle

    var body: some View {
        VStack {
            Spacer()
            Text("Waiting for data…")
                .font(.system(size: 12).italic())
                .foregroundStyle(widgetIdle ? Color.white.opacity(0.55) : Color(nsColor: .tertiaryLabelColor))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Card chrome background: Liquid Glass card, AppKit material, or opaque
/// (Reduce Transparency) — see GlassMode. In glass mode the readable state's
/// material is the AppKit NSGlassEffectView behind the hosting view (live
/// backdrop sampling); the idle translucent state is SwiftUI `Glass.clear`.
struct CardBackground: View {
    let mode: GlassMode
    let interacting: Bool

    var body: some View {
        switch mode {
        case .glass:
            if interacting {
                // Readable material comes from the AppKit NSGlassEffectView
                // behind the hosting view — no SwiftUI glass here (stacking
                // two materials would wash the card out).
                Color.clear
            } else {
                Color.clear
                    .glassEffect(Glass.clear,
                                 in: .rect(cornerRadius: Theme.cornerRadius))
            }
        case .material:
            // The AppKit NSVisualEffectView sits behind the hosting view;
            // SwiftUI layer stays clear.
            Color.clear
        case .solid:
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }
}
