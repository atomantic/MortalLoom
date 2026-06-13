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

extension String {
    /// Maps a semantic color name — as returned by the engines' `color`
    /// computed vars ("green"/"blue"/"yellow"/"orange"/"red") — to its adaptive
    /// `Color`. Single source of truth for the mapping the views previously each
    /// duplicated as a private `colorForName(_:)`.
    var semanticColor: Color {
        switch self {
        case "green": return .success
        case "blue": return .accentColor
        case "yellow": return .warning
        case "orange": return .orange
        case "red": return .danger
        default: return .textSecondary
        }
    }
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

    /// Whole days elapsed since `dateStr` (an ISO "yyyy-MM-dd"). Returns 0
    /// when the string is unparseable so callers don't have to branch.
    static func daysSince(_ dateStr: String, now: Date = Date()) -> Int {
        guard let date = dateFromString(dateStr) else { return 0 }
        return Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
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

/// Leading-aligned label + value stat tile with an optional secondary line.
/// Consolidates the near-identical `statCard` helpers that previously lived in
/// BodyView and SleepView (label on top, value below, an optional detail/date line).
struct StatCell: View {
    let label: String
    let value: String
    /// Optional descriptive line under the value (e.g. SleepView's "below target").
    var secondary: String? = nil
    /// Optional date line under the value, rendered abbreviated (e.g. BodyView's measurement date).
    var date: Date? = nil
    var valueColor: Color = .textPrimary
    var valueFont: Font = .subheadline
    var valueWeight: Font.Weight = .semibold

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.textMuted)
            Text(value)
                .font(valueFont)
                .fontWeight(valueWeight)
                .foregroundColor(valueColor)
            if let secondary {
                Text(secondary)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(secondary.map { "\(label): \(value), \($0)" } ?? "\(label): \(value)")
    }
}

/// Centered icon + value + label badge on a subtle background.
/// Consolidates the centered stat cards from LifeCalendarView (compact, input
/// background) and the Overview vitals row (prominent, card background).
struct StatBadge: View {
    enum Size { case compact, prominent }

    let value: String
    let label: String
    let icon: String
    var tint: Color = .accentColor
    var size: Size = .compact
    /// Overrides the default "<value> <label>" combined accessibility label.
    var accessibilityText: String? = nil

    var body: some View {
        VStack(spacing: size == .prominent ? 6 : 4) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .font(size == .prominent ? .title3 : .caption)
            Text(value)
                .font(size == .prominent ? .title2 : .headline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(size == .prominent ? .caption : .caption2)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .modifier(StatBadgeBackground(size: size))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText ?? "\(value) \(label)")
    }
}

private struct StatBadgeBackground: ViewModifier {
    let size: StatBadge.Size

    func body(content: Content) -> some View {
        switch size {
        case .compact:
            content
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(Color.bgInput.opacity(0.5))
                .cornerRadius(8)
        case .prominent:
            content
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .cardStyle()
        }
    }
}

/// Tappable summary tile used in the Overview health grid: an icon header, one or
/// more value lines (supplied via `content`), and a muted footer label, wrapped in
/// a card-styled button. An optional `header` accessory renders a trailing badge
/// next to the icon (e.g. the alcohol risk pill).
struct HealthSummaryTile<Header: View, Content: View>: View {
    let icon: String
    let iconColor: Color
    let label: String
    let accessibilityLabel: String
    var accessibilityHint: String? = nil
    let action: () -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .font(.title3)
                    Spacer()
                    header()
                }
                content()
                Text(label)
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

extension HealthSummaryTile where Header == EmptyView {
    init(
        icon: String,
        iconColor: Color,
        label: String,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            label: label,
            accessibilityLabel: accessibilityLabel,
            accessibilityHint: accessibilityHint,
            action: action,
            header: { EmptyView() },
            content: content
        )
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

    /// Applies `.formStyle(.grouped)` on macOS so Form rows lay out in the
    /// System-Settings-style label/value columns instead of the older plain
    /// list. No-op on iOS where Form already uses grouped rendering.
    func macGroupedFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    /// Sheet frame sized for macOS form modals (Goal edit, Check-in, etc.).
    /// macOS default sheets are ~420pt wide — too narrow for a labeled form.
    /// No-op on iOS where sheets fill the screen or use detents.
    func macSheetFrame(minHeight: CGFloat = 600, idealHeight: CGFloat = 720) -> some View {
        #if os(macOS)
        frame(minWidth: 560, idealWidth: 640, minHeight: minHeight, idealHeight: idealHeight)
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
