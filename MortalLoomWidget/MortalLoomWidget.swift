import WidgetKit
import SwiftUI

// MARK: - Snapshot Model (must match WidgetBridge.Snapshot in main app)

struct WidgetGoal: Codable, Sendable {
    let title: String
    let targetDate: Date?
    let progressPercent: Double
    let isOverdue: Bool
    let needsCheckIn: Bool
    let category: String?
}

struct WidgetSnapshot: Codable, Sendable {
    let goals: [WidgetGoal]
    let activeCount: Int
    let overdueCount: Int
    let needsCheckInCount: Int
    let healthScore: Double
    let updatedAt: Date
    let apexTitle: String?
    let alignmentScore: Double?
    let todaysPrompt: String?
    let apexGoalId: UUID?

    // Back-compat decoder: older snapshot files (written by pre-alignment
    // builds) don't have the new fields. Default them to nil.
    private enum CodingKeys: String, CodingKey {
        case goals, activeCount, overdueCount, needsCheckInCount, healthScore, updatedAt
        case apexTitle, alignmentScore, todaysPrompt, apexGoalId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goals = try c.decode([WidgetGoal].self, forKey: .goals)
        activeCount = try c.decode(Int.self, forKey: .activeCount)
        overdueCount = try c.decode(Int.self, forKey: .overdueCount)
        needsCheckInCount = try c.decode(Int.self, forKey: .needsCheckInCount)
        healthScore = try c.decode(Double.self, forKey: .healthScore)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        apexTitle = try c.decodeIfPresent(String.self, forKey: .apexTitle)
        alignmentScore = try c.decodeIfPresent(Double.self, forKey: .alignmentScore)
        todaysPrompt = try c.decodeIfPresent(String.self, forKey: .todaysPrompt)
        apexGoalId = try c.decodeIfPresent(UUID.self, forKey: .apexGoalId)
    }

    // Explicit init so the placeholder can construct one.
    init(
        goals: [WidgetGoal],
        activeCount: Int,
        overdueCount: Int,
        needsCheckInCount: Int,
        healthScore: Double,
        updatedAt: Date,
        apexTitle: String? = nil,
        alignmentScore: Double? = nil,
        todaysPrompt: String? = nil,
        apexGoalId: UUID? = nil
    ) {
        self.goals = goals
        self.activeCount = activeCount
        self.overdueCount = overdueCount
        self.needsCheckInCount = needsCheckInCount
        self.healthScore = healthScore
        self.updatedAt = updatedAt
        self.apexTitle = apexTitle
        self.alignmentScore = alignmentScore
        self.todaysPrompt = todaysPrompt
        self.apexGoalId = apexGoalId
    }
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
            goals: [
                WidgetGoal(title: "Write a book", targetDate: Calendar.current.date(byAdding: .month, value: 6, to: Date()), progressPercent: 35, isOverdue: false, needsCheckIn: true, category: "creative"),
                WidgetGoal(title: "Run a marathon", targetDate: Calendar.current.date(byAdding: .month, value: 3, to: Date()), progressPercent: 60, isOverdue: false, needsCheckIn: false, category: "health"),
            ],
            activeCount: 5,
            overdueCount: 1,
            needsCheckInCount: 2,
            healthScore: 82,
            updatedAt: Date(),
            apexTitle: "Leave a lasting creative legacy",
            alignmentScore: 62,
            todaysPrompt: "What's holding you back right now?",
            apexGoalId: UUID()
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
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Helpers

private func daysUntil(_ date: Date, from now: Date = Date()) -> Int {
    Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
}

private func dueDateLabel(_ date: Date, from now: Date = Date()) -> String {
    let days = daysUntil(date, from: now)
    if days < 0 { return "\(abs(days))d overdue" }
    if days == 0 { return "Due today" }
    if days == 1 { return "Due tomorrow" }
    if days < 7 { return "Due in \(days)d" }
    if days < 30 { return "Due in \(days / 7)w" }
    return "Due in \(days / 30)mo"
}

private func urgencyColor(_ goal: WidgetGoal) -> Color {
    if goal.isOverdue { return .red }
    if goal.needsCheckIn { return .orange }
    guard let target = goal.targetDate else { return .blue }
    let days = daysUntil(target)
    if days <= 7 { return .red }
    if days <= 30 { return .orange }
    return .blue
}

private func categoryIcon(_ category: String?) -> String {
    switch category {
    case "health": return "heart.fill"
    case "creative": return "paintbrush.fill"
    case "family": return "person.2.fill"
    case "financial": return "dollarsign.circle.fill"
    case "legacy": return "star.fill"
    case "mastery": return "graduationcap.fill"
    default: return "target"
    }
}

/// Deep link for a widget tap. When an apex is set we route to the apex
/// reflect sheet so the tap is a 2-tap reflection; otherwise we fall back
/// to the overview or goals page depending on whether standard goals exist.
/// Returns nil on snapshots that can't be meaningfully routed — the widget
/// then falls back to the default "launch the app" behaviour.
private func tapURL(for snapshot: WidgetSnapshot?) -> URL? {
    guard let snapshot else { return URL(string: "mortalloom://overview") }
    if let id = snapshot.apexGoalId {
        return URL(string: "mortalloom://goal/\(id.uuidString)/reflect")
    }
    if !snapshot.goals.isEmpty {
        return URL(string: "mortalloom://goals")
    }
    return URL(string: "mortalloom://overview")
}

// MARK: - Entry View Router

struct MortalLoomWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MortalLoomEntry

    var body: some View {
        content
            .widgetURL(tapURL(for: entry.snapshot))
    }

    @ViewBuilder
    private var content: some View {
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
        if let snapshot = entry.snapshot, let apexTitle = snapshot.apexTitle {
            // North Star mode: lead with apex title + alignment %
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("North Star")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                }
                Text(apexTitle)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                if let alignment = snapshot.alignmentScore {
                    Text("\(Int(alignment))%")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(alignmentColor(alignment))
                    Text("aligned")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                } else {
                    Text("Tap to add\nsupporting goals")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else if let snapshot = entry.snapshot, let top = snapshot.goals.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: categoryIcon(top.category))
                        .font(.caption)
                        .foregroundStyle(urgencyColor(top))
                    Text("MortalLoom")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(top.title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(2)

                if let target = top.targetDate {
                    Text(dueDateLabel(target, from: entry.date))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(urgencyColor(top))
                }

                Spacer(minLength: 0)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(urgencyColor(top))
                            .frame(width: geo.size.width * min(1, top.progressPercent / 100), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(String(format: "%.0f%%", top.progressPercent))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    if snapshot.overdueCount > 0 {
                        Text("\(snapshot.overdueCount) overdue")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    } else if snapshot.needsCheckInCount > 0 {
                        Text("\(snapshot.needsCheckInCount) need check-in")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Set goals in\nMortalLoom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

/// Color for the alignment percentage on the widget. Mirrors the main-app
/// scale (off-track → drifting → mostly → on track → deeply).
private func alignmentColor(_ score: Double) -> Color {
    switch score {
    case ..<30: .red
    case 30..<50: .orange
    case 50..<70: .blue
    default: .green
    }
}

// MARK: - Medium Widget (Home Screen)

struct MediumWidgetView: View {
    let entry: MortalLoomEntry

    var body: some View {
        if let snapshot = entry.snapshot, let apexTitle = snapshot.apexTitle {
            // North Star + top goals
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text("NORTH STAR")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }
                        Text(apexTitle)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                    }
                    Spacer()
                    if let alignment = snapshot.alignmentScore {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(Int(alignment))%")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(alignmentColor(alignment))
                            Text("aligned")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                ForEach(Array(snapshot.goals.prefix(2).enumerated()), id: \.offset) { _, goal in
                    goalRow(goal)
                }

                if let prompt = snapshot.todaysPrompt {
                    Text(prompt)
                        .font(.system(size: 9, weight: .medium))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else if let snapshot = entry.snapshot, !snapshot.goals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "target")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Goals")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(snapshot.activeCount) active")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(snapshot.goals.prefix(3).enumerated()), id: \.offset) { _, goal in
                    goalRow(goal)
                }

                if snapshot.overdueCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                        Text("\(snapshot.overdueCount) overdue")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Open MortalLoom to set your life goals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private func goalRow(_ goal: WidgetGoal) -> some View {
        HStack(spacing: 8) {
            Image(systemName: categoryIcon(goal.category))
                .font(.system(size: 10))
                .foregroundStyle(urgencyColor(goal))
                .frame(width: 14)

            Text(goal.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let target = goal.targetDate {
                Text(dueDateLabel(target, from: entry.date))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(urgencyColor(goal))
            }

            Text(String(format: "%.0f%%", goal.progressPercent))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lock Screen: Circular Gauge

struct CircularWidgetView: View {
    let entry: MortalLoomEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let overdue = snapshot.overdueCount
            if overdue > 0 {
                ZStack {
                    Gauge(value: Double(overdue), in: 0...max(Double(snapshot.activeCount), 1)) {
                        Image(systemName: "exclamationmark.triangle.fill")
                    } currentValueLabel: {
                        Text("\(overdue)")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(.red)
                }
                .containerBackground(.fill.tertiary, for: .widget)
            } else {
                Gauge(value: Double(snapshot.activeCount), in: 0...max(Double(snapshot.activeCount), 1)) {
                    Image(systemName: "target")
                } currentValueLabel: {
                    Text("\(snapshot.activeCount)")
                        .font(.system(size: 14, weight: .bold))
                }
                .gaugeStyle(.accessoryCircular)
                .containerBackground(.fill.tertiary, for: .widget)
            }
        } else {
            Image(systemName: "target")
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Lock Screen: Rectangular

struct RectangularWidgetView: View {
    let entry: MortalLoomEntry

    var body: some View {
        if let snapshot = entry.snapshot, let top = snapshot.goals.first {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .font(.caption2)
                    Text("MortalLoom")
                        .font(.caption2).bold()
                }

                Text(top.title)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .lineLimit(1)

                if let target = top.targetDate {
                    Text(dueDateLabel(target, from: entry.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            Text("Set goals in MortalLoom")
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
            if snapshot.overdueCount > 0 {
                Text("\(snapshot.overdueCount) overdue goal\(snapshot.overdueCount == 1 ? "" : "s")")
            } else if let top = snapshot.goals.first, let target = top.targetDate {
                Text("\(top.title): \(dueDateLabel(target, from: entry.date))")
            } else {
                Text("\(snapshot.activeCount) active goals")
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
        .configurationDisplayName("Goals")
        .description("Track your life goals, deadlines, and check-ins")
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
