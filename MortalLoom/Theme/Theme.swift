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

    // Table row alternating background
    #if os(iOS)
    static let tableRowAlt = Color(.systemGray5).opacity(0.5)
    #else
    static let tableRowAlt = Color(.separatorColor).opacity(0.12)
    #endif
}

// MARK: - Shared Date Formatting

enum DateFormatting {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
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

    static func dateString(daysAgo: Int, from now: Date = Date()) -> String {
        dateString(Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now)
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

    static func formatDuration(_ days: Int) -> String {
        if days < 7 { return "\(days)d" }
        if days < 30 { return "\(days / 7)w" }
        if days < 365 { return "\(days / 30)mo" }
        let years = days / 365
        let remainingMonths = (days % 365) / 30
        if remainingMonths == 0 { return "\(years)y" }
        return "\(years)y \(remainingMonths)mo"
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Layout Constants

enum Layout {
    static let chartFrameHeight: CGFloat = 160
    static let wideThreshold: CGFloat = 700
    @MainActor static var defaultContainerWidth: CGFloat {
        #if os(iOS)
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width) ?? 390
        #else
        900
        #endif
    }
}

// MARK: - Container Width Reader

extension View {
    func readContainerWidth(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { geo in
            Color.clear
                .onAppear { action(geo.size.width) }
                .onChange(of: geo.size.width) { _, w in action(w) }
        })
    }
}

// MARK: - Card Style Modifier

struct CardStyle: ViewModifier {
    let fill: Color
    let border: Color
    let radius: CGFloat

    init(fill: Color = .bgCard, border: Color = .cardBorder, radius: CGFloat = 12) {
        self.fill = fill
        self.border = border
        self.radius = radius
    }

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(border, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle(fill: Color = .bgCard, border: Color = .cardBorder, radius: CGFloat = 12) -> some View {
        modifier(CardStyle(fill: fill, border: border, radius: radius))
    }

    /// Applies `.navigationBarTitleDisplayMode(.inline)` on iOS only.
    /// On macOS, `NavigationStack` already lays titles inline so the modifier is a no-op.
    /// Replaces 12+ inline `#if os(iOS)` guards across the views.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - Pro Brand Gradient

extension LinearGradient {
    static let proBrand = LinearGradient(
        colors: [.accentColor, .purple], startPoint: .leading, endPoint: .trailing
    )
    static let proBrandDiagonal = LinearGradient(
        colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let proBrandSubtleDiagonal = LinearGradient(
        colors: [Color.accentColor.opacity(0.12), Color.purple.opacity(0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Toast Notification

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let icon: String
    let tint: Color

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            Group {
                if let message {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.body.weight(.semibold))
                        Text(message)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(tint.opacity(0.92))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                }
            }
            .animation(.spring(duration: 0.35), value: message)
        }
    }
}

extension View {
    func toast(_ message: Binding<String?>, icon: String = "checkmark.circle.fill", tint: Color = .success) -> some View {
        modifier(ToastModifier(message: message, icon: icon, tint: tint))
    }
}

func showToast(_ binding: Binding<String?>, message: String, duration: TimeInterval = 2.0) {
    binding.wrappedValue = message
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(duration))
        if binding.wrappedValue == message {
            binding.wrappedValue = nil
        }
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
