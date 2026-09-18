import AppKit
import SwiftUI

/// True while the card is in the translucent native-widget state (idle):
/// every label and icon renders in the widget's monochrome scheme (white/gray
/// tiers in dark mode, dark/gray tiers in light mode).
private struct WidgetIdleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var widgetIdle: Bool {
        get { self[WidgetIdleKey.self] }
        set { self[WidgetIdleKey.self] = newValue }
    }
}

/// Idle (unfocused) palette. Native desktop widgets render their content
/// monochrome when the desktop isn't frontmost — every label and icon drops to
/// one brightness tier, with no hue left anywhere. Semantics the focused card
/// carries with hue (importance, beat/miss) become brightness tiers here.
///
/// The ladder is appearance-adaptive: dark mode keeps the white/gray tiers over
/// dark glass, light mode mirrors them into dark/gray tiers over the bright
/// glass veil. A white-text card is only readable if the card is scrimmed
/// black — and that scrim is what made the unfocused LIGHT card read as a
/// dark-mode slab instead of a light widget.
enum IdlePalette {
    /// One neutral tier, resolved by the effective appearance: white at
    /// `dark` in dark mode, black at `light` in light mode. Both are the same
    /// ramp — only the anchor flips — so every call site keeps using the plain
    /// `IdlePalette.x` constant and both appearances come out of one table.
    private static func tier(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark)
                : NSColor(white: 0, alpha: light)
        })
    }

    static let primary = tier(light: 0.88, dark: 1.00)
    static let secondary = tier(light: 0.55, dark: 0.62)
    static let tertiary = tier(light: 0.30, dark: 0.40)
    static let hairline = tier(light: 0.09, dark: 0.12)

    static let rowFill = tier(light: 0.04, dark: 0.05)
    static let highImpactFill = tier(light: 0.07, dark: 0.10)
    static let highImpactHover = tier(light: 0.11, dark: 0.16)

    /// Neutral replacement for the accent color (now-divider, selected chips).
    static let accent = tier(light: 0.65, dark: 0.80)
    static let accentTint = tier(light: 0.12, dark: 0.22)

    static let starLow = tier(light: 0.30, dark: 0.35)
    static let starMedium = tier(light: 0.55, dark: 0.62)
    static let starHigh = tier(light: 0.85, dark: 0.95)

    static let beat = tier(light: 0.85, dark: 0.95)
    static let miss = tier(light: 0.45, dark: 0.55)
}

/// Shared metrics, dynamic (light/dark adaptive) colors, and formatters.
/// The Qt app's hardcoded light-only palette is replaced by system colors so
/// both appearances come out right automatically.
enum Theme {
    /// Matches the system desktop-widget corner radius.
    static let cornerRadius: CGFloat = 26
    static let titleBarHeight: CGFloat = 44
    static let filterBarHeight: CGFloat = 38
    static let headerHeight: CGFloat = 28
    static let statusHeight: CGFloat = 20
    static let horizontalPadding: CGFloat = 14

    // Column widths — port of widget.COL_WIDTHS.
    static let colTime: CGFloat = 60
    static let colCurrency: CGFloat = 64
    static let colImportance: CGFloat = 48
    static let colActual: CGFloat = 76
    static let colForecast: CGFloat = 86
    static let colPrevious: CGFloat = 80

    /// Neutral veil the translucent idle card draws over the glass — the one
    /// layer that makes the card match its appearance's widget look:
    /// dark mode darkens slightly (the wallpaper's own tone, white text stays
    /// legible), light mode lifts slightly (the bright light widget, dark text
    /// stays legible). Without the light half, dark text sits on whatever the
    /// wallpaper happens to be, and the card reads as a milky see-through film.
    static func idleVeil(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.10) : Color.white.opacity(0.16)
    }

    /// Outer dark ring of the "凝光" card edge. The dark card needs a strong
    /// ring to separate it from the wallpaper; on the bright light card the
    /// same value reads as a heavy black outline.
    static func idleRingOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.20 : 0.10
    }

    // Importance star colors: 1 gray / 2 orange / 3 red (investing.com scheme)
    // when focused; white/gray brightness tiers when idle.
    static func importanceColor(_ level: Importance, idle: Bool = false) -> Color {
        if idle {
            switch level {
            case .low: return IdlePalette.starLow
            case .medium: return IdlePalette.starMedium
            case .high: return IdlePalette.starHigh
            }
        }
        switch level {
        case .low: return Color(nsColor: .systemGray)
        case .medium: return Color(nsColor: .systemOrange)
        case .high: return Color(nsColor: .systemRed)
        }
    }

    static let beatColor = Color(nsColor: .systemGreen)
    static let missColor = Color(nsColor: .systemRed)

    /// '🇺🇸 US' style label; falls back to bare code — port of _flag_and_code.
    static func flagLabel(_ currency: String) -> String {
        if let info = CountryMaps.currencyFlags[currency.uppercased()] {
            return "\(info.flag) \(info.code)"
        }
        return "  \(currency)"
    }

    // MARK: Formatters (Asia/Shanghai, parity with the legacy display)

    private static func shanghaiFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = EventParsing.localTimeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    private static let timeFormatter = shanghaiFormatter("HH:mm")
    private static let tooltipTimeFormatter = shanghaiFormatter("yyyy-MM-dd HH:mm zzz")

    static func hhmm(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func tooltipTime(_ date: Date) -> String { tooltipTimeFormatter.string(from: date) }
}
