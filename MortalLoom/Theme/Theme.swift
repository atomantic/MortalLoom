import SwiftUI

// MARK: - Semantic Color Aliases (Apple Design Standards)
//
// Use SwiftUI's built-in adaptive colors instead of custom values.
// These automatically adapt to light/dark mode, accessibility settings,
// and platform conventions.

extension Color {
    // Backgrounds — use system groupedBackground which adapts per platform
    static let bg = Color(.systemGroupedBackground)
    static let bgCard = Color(.secondarySystemGroupedBackground)
    static let bgInput = Color(.tertiarySystemGroupedBackground)

    // Card border — system separator adapts to light/dark
    static let cardBorder = Color(.separator)

    // Text — semantic system labels
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textMuted = Color(.tertiaryLabel)

    // Status — use system-standard colors
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
}

// MARK: - Shared Date Formatting

enum DateFormatting {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let largeNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    static func todayString() -> String {
        isoFormatter.string(from: Date())
    }

    static func dateString(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func dateFromString(_ str: String) -> Date? {
        isoFormatter.date(from: str)
    }

    static func displayDate(_ isoString: String) -> String {
        guard let date = isoFormatter.date(from: isoString) else { return isoString }
        return displayFormatter.string(from: date)
    }

    static func formatLargeNumber(_ value: Int) -> String {
        largeNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formatMarkerValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

// MARK: - Shared UI Components

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.textMuted)
            .tracking(1)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(.textMuted)
            Text(title)
                .font(.headline)
                .foregroundColor(.textSecondary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
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

// MARK: - Cross-Platform Keyboard Type

#if os(macOS)
// Map iOS UIColor semantic names to NSColor equivalents
extension NSColor {
    static let systemGroupedBackground = NSColor.windowBackgroundColor
    static let secondarySystemGroupedBackground = NSColor.controlBackgroundColor
    static let tertiarySystemGroupedBackground = NSColor.textBackgroundColor
    static let label = NSColor.labelColor
    static let secondaryLabel = NSColor.secondaryLabelColor
    static let tertiaryLabel = NSColor.tertiaryLabelColor
    static let separator = NSColor.separatorColor
}

// No-op on macOS where keyboardType doesn't exist
enum UIKeyboardType { case decimalPad, numberPad, `default` }

extension View {
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
}
#endif
