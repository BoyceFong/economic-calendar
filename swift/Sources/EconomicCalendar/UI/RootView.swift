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
            // Glass edge highlight ("凝光"): a bright specular rim, most
            // visible in the idle widget state — as on native desktop widgets.
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(model.isIdle ? 0.65 : 0.28), location: 0),
                            .init(color: .white.opacity(model.isIdle ? 0.10 : 0.05), location: 0.5),
                            .init(color: .white.opacity(model.isIdle ? 0.45 : 0.16), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2)
        }
        .environment(\.widgetIdle, model.isIdle)
        .contextMenu {
            ContextMenuContent(event: nil)
        }
    }
}
