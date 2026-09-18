import SwiftUI

/// Card root: Liquid Glass background + title bar / filter bar / list / status.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppActions.self) private var actions

    var body: some View {
        ZStack {
            CardBackground(mode: model.glassMode, interacting: model.isInteracting)

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
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .onHover { model.setHovering($0) }
        .contextMenu {
            ContextMenuContent(event: nil)
        }
    }
}
