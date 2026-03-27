import WidgetKit
import SwiftUI

// MARK: - Snapshot Model (must match WidgetBridge.Snapshot in main app)

struct WidgetSnapshot: Codable, Sendable {
    let deathDate: Date
    let percentComplete: Double
    let yearsRemaining: Double
    let healthScore: Double
    let ageYears: Int
    let lifeExpectancy: Double
    let updatedAt: Date
}

// MARK: - Data Loading

enum WidgetDataLoader: Sendable {
    static let appGroupID = "group.net.shadowpuppet.MeatSpaceTracker"

    static func load() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                .appendingPathComponent("widget-snapshot.json"),
              let raw = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: raw)
    }
}

// MARK: - Timeline

struct MortalLoomEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    static let placeholder = MortalLoomEntry(
        date: Date(),
        snapshot: WidgetSnapshot(
            deathDate: Calendar.current.date(byAdding: .year, value: 35, to: Date())!,
            percentComplete: 55.0,
            yearsRemaining: 35.2,
            healthScore: 82.0,
            ageYears: 43,
            lifeExpectancy: 78.2,
            updatedAt: Date()
        )
    )
}

struct MortalLoomProvider: TimelineProvider {
    func placeholder(in context: Context) -> MortalLoomEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (MortalLoomEntry) -> Void) {
        let snapshot = WidgetDataLoader.load()
        completion(MortalLoomEntry(date: Date(), snapshot: snapshot ?? MortalLoomEntry.placeholder.snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<MortalLoomEntry>) -> Void) {
        let snapshot = WidgetDataLoader.load()
        let now = Date()
        let entry = MortalLoomEntry(date: now, snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Countdown

struct CountdownComponents {
    let years: Int
    let months: Int
    let weeks: Int
    let days: Int
    let hours: Int
    let minutes: Int
    let expired: Bool

    init(from now: Date, to deathDate: Date) {
        let diff = deathDate.timeIntervalSince(now)
        guard diff > 0 else {
            self.init(years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, expired: true)
            return
        }
        let totalSeconds = Int(diff)
        let totalMinutes = totalSeconds / 60
        let totalHours = totalMinutes / 60
        let totalDays = totalHours / 24

        let y = Int(Double(totalDays) / 365.25)
        let daysAfterYears = totalDays - Int(Double(y) * 365.25)
        let mo = Int(Double(daysAfterYears) / 30.44)
        let daysAfterMonths = daysAfterYears - Int(Double(mo) * 30.44)
        let w = daysAfterMonths / 7
        let d = daysAfterMonths - w * 7

        self.init(
            years: y, months: mo, weeks: w, days: d,
            hours: totalHours % 24, minutes: totalMinutes % 60, expired: false
        )
    }

    private init(years: Int, months: Int, weeks: Int, days: Int, hours: Int, minutes: Int, expired: Bool) {
        self.years = years
        self.months = months
        self.weeks = weeks
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.expired = expired
    }
}

// MARK: - Color Helpers

private func progressColor(_ percent: Double) -> Color {
    if percent >= 80 { return .red }
    if percent >= 60 { return .orange }
    return .blue
}

// MARK: - Entry View Router

struct MortalLoomWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MortalLoomEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
        case .accessoryInline:
            InlineWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget (Home Screen)

struct SmallWidgetView: View {
    let entry: MortalLoomEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let cd = CountdownComponents(from: entry.date, to: snapshot.deathDate)
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: min(1, snapshot.percentComplete / 100))
                        .stroke(progressColor(snapshot.percentComplete),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f%%", snapshot.percentComplete))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("lived")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 70, height: 70)

                if cd.expired {
                    Text("Time's up")
                        .font(.caption).bold()
                        .foregroundStyle(.red)
                } else {
                    HStack(spacing: 4) {
                        pill(cd.years, "Y", .blue)
                        pill(cd.months, "M", .purple)
                        pill(cd.weeks, "W", .teal)
                        pill(cd.days, "D", .green)
                    }

                    Text("\(String(format: "%.1f", snapshot.yearsRemaining)) years left")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            unconfiguredSmall
        }
    }

    private func pill(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 30)
    }

    private var unconfiguredSmall: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Open MortalLoom\nto configure")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget (Home Screen)

struct MediumWidgetView: View {
    let entry: MortalLoomEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let cd = CountdownComponents(from: entry.date, to: snapshot.deathDate)
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(1, snapshot.percentComplete / 100))
                        .stroke(progressColor(snapshot.percentComplete),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(String(format: "%.1f%%", snapshot.percentComplete))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("lived")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Time Remaining")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if cd.expired {
                        Text("Time's up.")
                            .font(.headline).bold()
                            .foregroundStyle(.red)
                    } else {
                        HStack(spacing: 3) {
                            unit(cd.years, "Y", .blue)
                            colon
                            unit(cd.months, "Mo", .purple)
                            colon
                            unit(cd.weeks, "W", .teal)
                            colon
                            unit(cd.days, "D", .green)
                            colon
                            unit(cd.hours, "H", .yellow)
                            colon
                            unit(cd.minutes, "M", .orange)
                        }
                    }

                    HStack(spacing: 16) {
                        stat("Health", String(format: "%.0f", snapshot.healthScore), .green)
                        stat("LE", String(format: "%.1fy", snapshot.lifeExpectancy), .blue)
                        stat("Age", "\(snapshot.ageYears)", .purple)
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Open MortalLoom to configure your death clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private func unit(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.tertiary)
            .padding(.bottom, 10)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lock Screen: Circular Gauge

struct CircularWidgetView: View {
    let entry: MortalLoomEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            Gauge(value: min(1, snapshot.percentComplete / 100)) {
                Image(systemName: "clock.fill")
            } currentValueLabel: {
                Text(String(format: "%.0f%%", snapshot.percentComplete))
                    .font(.system(size: 12, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            Image(systemName: "clock.fill")
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Lock Screen: Rectangular

struct RectangularWidgetView: View {
    let entry: MortalLoomEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let cd = CountdownComponents(from: entry.date, to: snapshot.deathDate)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                    Text("MortalLoom")
                        .font(.caption2).bold()
                }

                if cd.expired {
                    Text("Time's up.")
                        .font(.headline)
                } else {
                    Text("\(cd.years)Y \(cd.months)Mo \(cd.weeks)W \(cd.days)D")
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text(String(format: "%.1f years remaining", snapshot.yearsRemaining))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            Text("Configure MortalLoom")
                .font(.caption)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Lock Screen: Inline

struct InlineWidgetView: View {
    let entry: MortalLoomEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let cd = CountdownComponents(from: entry.date, to: snapshot.deathDate)
            if cd.expired {
                Text("MortalLoom: Time's up")
            } else {
                Text("\(cd.years)y \(cd.months)mo \(cd.weeks)w remaining")
            }
        } else {
            Text("MortalLoom")
        }
    }
}

// MARK: - Widget Definition

struct MortalLoomWidget: Widget {
    let kind = "MortalLoomWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MortalLoomProvider()) { entry in
            MortalLoomWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Death Clock")
        .description("Your life countdown and health score")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

@main
struct MortalLoomWidgetBundle: WidgetBundle {
    var body: some Widget {
        MortalLoomWidget()
    }
}
