import SwiftUI

/// Importance filter — min-importance semantics identical to the legacy
/// "Min importance" menu (All ≡ Low ≥1, Med+ ≥2, High ≥3) rendered as glass
/// chips. Chips are tap targets with glass backgrounds (no Button/interactive
/// glass), so clicks register instantly even in the non-activating panel.
struct ImportanceFilterChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                chip(.low) {
                    Text("All")
                        .font(.system(size: 11, weight: .semibold))
                }
                chip(.medium) {
                    StarsView(level: .medium, size: 8, gap: 1)
                }
                chip(.high) {
                    // Three red stars — investing.com's high-impact mark.
                    StarsView(level: .high, size: 8, gap: 1)
                }
            }
        }
        .help("Filter by minimum importance")
    }

    @ViewBuilder
    private func chip<Label: View>(_ threshold: Importance, @ViewBuilder label: () -> Label) -> some View {
        let selected = model.minImportance == threshold
        label()
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassEffect(
                selected
                    ? Glass.regular.tint(Color.accentColor)
                    : Glass.regular,
                in: .capsule)
            .contentShape(.capsule)
            .onTapGesture {
                guard model.minImportance != threshold else { return }
                model.minImportance = threshold
            }
    }
}

/// Country/currency filter chip opening a multi-select popover.
/// Currencies are derived from the current dataset (menu parity), and the
/// selection persists across launches.
struct CurrencyFilterButton: View {
    @Environment(AppModel.self) private var model

    @State private var showingPopover = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(.system(size: 11))
            if !model.selectedCurrencies.isEmpty {
                Text("\(model.selectedCurrencies.count)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(
            model.selectedCurrencies.isEmpty ? Color.primary.opacity(0.85) : Color.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassEffect(
            model.selectedCurrencies.isEmpty
                ? Glass.regular
                : Glass.regular.tint(Color.accentColor),
            in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { showingPopover = true }
        .help("Filter by country / currency")
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            CurrencyPopoverView()
                .frame(width: 270)
        }
    }
}

struct CurrencyPopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Currencies")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 6)], spacing: 6) {
                ForEach(model.availableCurrencies, id: \.self) { currency in
                    chip(currency)
                }
            }

            if !model.selectedCurrencies.isEmpty {
                Button("All currencies") {
                    model.selectedCurrencies = []
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            if model.availableCurrencies.isEmpty {
                Text("Waiting for data…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func chip(_ currency: String) -> some View {
        let selected = model.selectedCurrencies.contains(currency)
        Text(currency)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onTapGesture {
                if selected {
                    model.selectedCurrencies.remove(currency)
                } else {
                    model.selectedCurrencies.insert(currency)
                }
            }
    }
}

/// The filter bar row under the title.
struct FilterBarView: View {
    var body: some View {
        HStack(spacing: 8) {
            ImportanceFilterChips()
            CurrencyFilterButton()
            Spacer()
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .frame(height: Theme.filterBarHeight)
    }
}
