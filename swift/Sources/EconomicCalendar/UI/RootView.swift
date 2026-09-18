import SwiftUI

/// Card root: Liquid Glass background + title bar / filter bar / list / status.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppActions.self) private var actions

    var body: some View {
        ZStack {
            CardBackground(mode: model.glassMode)

            VStack(spacing: 0) {
                TitleBarView()
                FilterBarView()
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                ColumnHeaderView()
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                ZStack {
                    if model.displayRows.isEmpty {
                        WaitingView()
                    } else {
                        EventListView(
                            rows: model.displayRows,
                            scrollToken: model.scrollToken,
                            scrollReason: model.scrollReason)
                    }
                }
                .frame(maxHeight: .infinity)

                StatusView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay {
            // Glass edge highlight ("凝光"): dark outer ring + bright specular
            // inner rim (brighter when idle) — visible on any wallpaper.
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Color.black.opacity(model.isIdle ? 0.20 : 0.10), lineWidth: 2)
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(model.isIdle ? 0.75 : 0.32), location: 0),
                                .init(color: .white.opacity(model.isIdle ? 0.14 : 0.06), location: 0.5),
                                .init(color: .white.opacity(model.isIdle ? 0.55 : 0.20), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.2)
            }
        }
        .environment(\.widgetIdle, model.isIdle)
        .contextMenu {
            ContextMenuContent(event: nil)
        }
    }
}
