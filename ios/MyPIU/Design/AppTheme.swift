import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.16, green: 0.79, blue: 0.31)
    static let positive = accent
    static let warning = Color(red: 0.93, green: 0.58, blue: 0.10)
    static let judgmentBad = Color(red: 0.55, green: 0.28, blue: 0.76)
    static let danger = Color(red: 0.83, green: 0.19, blue: 0.20)
    static let info = Color(red: 0.08, green: 0.48, blue: 0.85)
    static let levelBadgeBackground = Color(red: 0.09, green: 0.10, blue: 0.09)
    static let ink = adaptive(
        light: UIColor(red: 0.09, green: 0.10, blue: 0.09, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1)
    )
    static let mutedInk = adaptive(
        light: UIColor(red: 0.40, green: 0.44, blue: 0.37, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.69, blue: 0.63, alpha: 1)
    )
    static let border = adaptive(
        light: UIColor(red: 0.85, green: 0.87, blue: 0.82, alpha: 1),
        dark: UIColor(red: 0.23, green: 0.25, blue: 0.22, alpha: 1)
    )
    static let pageBackground = adaptive(
        light: UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1),
        dark: UIColor(red: 0.07, green: 0.08, blue: 0.07, alpha: 1)
    )
    static let cardBackground = adaptive(
        light: .white,
        dark: UIColor(red: 0.11, green: 0.13, blue: 0.10, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
