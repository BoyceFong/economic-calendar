import SwiftUI

/// Title row: name + event count, with the window drag region behind it.
struct TitleBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text("Economic Calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(model.titleCount)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .frame(height: Theme.titleBarHeight)
        .background(DragRegionView())
    }
}

/// Bottom status line — same texts as the Qt status bar.
struct StatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

/// Centered italic placeholder — port of the Qt empty state.
struct WaitingView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Waiting for data…")
                .font(.system(size: 12).italic())
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Card chrome background: Liquid Glass card, AppKit material, or opaque
/// (Reduce Transparency) — see GlassMode. While the user is on the widget the
/// card is readable `.regular` glass; idle it fades to `.clear`, matching the
/// translucent look of native desktop widgets (adapts to light/dark itself).
struct CardBackground: View {
    let mode: GlassMode
    let interacting: Bool

    var body: some View {
        switch mode {
        case .glass:
            Color.clear
                .glassEffect(interacting ? Glass.regular : Glass.clear,
                             in: .rect(cornerRadius: Theme.cornerRadius))
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
