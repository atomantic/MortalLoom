import SwiftUI

// MARK: - Adaptive Colors (light + dark mode)

extension Color {
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }
}

extension Color {
    // Backgrounds
    static let bg = Color(
        light: Color(red: 248/255, green: 250/255, blue: 252/255),
        dark: Color(red: 15/255, green: 23/255, blue: 42/255)
    )
    static let bgCard = Color(
        light: .white,
        dark: Color(red: 30/255, green: 41/255, blue: 59/255)
    )
    static let bgInput = Color(
        light: Color(red: 241/255, green: 245/255, blue: 249/255),
        dark: Color(red: 51/255, green: 65/255, blue: 85/255)
    )

    // Brand — health/vitality red
    static let accent = Color(red: 239/255, green: 68/255, blue: 68/255)     // red-500
    static let accentDark = Color(red: 220/255, green: 38/255, blue: 38/255)  // red-600

    // Card border
    static let cardBorder = Color(
        light: Color(red: 226/255, green: 232/255, blue: 240/255),
        dark: Color(red: 51/255, green: 65/255, blue: 85/255).opacity(0.5)
    )

    // Text
    static let textPrimary = Color(
        light: Color(red: 15/255, green: 23/255, blue: 42/255),
        dark: .white
    )
    static let textSecondary = Color(
        light: Color(red: 71/255, green: 85/255, blue: 105/255),
        dark: Color(red: 148/255, green: 163/255, blue: 184/255)
    )
    static let textMuted = Color(
        light: Color(red: 148/255, green: 163/255, blue: 184/255),
        dark: Color(red: 100/255, green: 116/255, blue: 139/255)
    )

    // Status
    static let success = Color(red: 34/255, green: 197/255, blue: 94/255)
    static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)
    static let danger = Color(red: 239/255, green: 68/255, blue: 68/255)
}

// MARK: - Layout Constants

enum Layout {
    static let chartFrameHeight: CGFloat = 160
}

// MARK: - Card Style Modifier

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgCard)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
