import SwiftUI

/// Shared metrics, dynamic (light/dark adaptive) colors, and formatters.
/// The Qt app's hardcoded light-only palette is replaced by system colors so
/// both appearances come out right automatically.
enum Theme {
    static let cornerRadius: CGFloat = 16
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

    // Importance star colors: 1 gray / 2 orange / 3 red (investing.com scheme).
    static func importanceColor(_ level: Importance) -> Color {
        switch level {
        case .low: Color(nsColor: .systemGray)
        case .medium: Color(nsColor: .systemOrange)
        case .high: Color(nsColor: .systemRed)
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
