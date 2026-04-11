import SwiftUI

// MARK: - ReflectionEntry

/// A single reflection check-in paired with the goal it belongs to.
/// Used as the row type for the Reflections list.
private struct ReflectionEntry: Identifiable {
    let id: UUID
    let goalId: UUID
    let goalTitle: String
    let goalType: GoalType?
    let checkIn: GoalCheckIn

    init(checkIn: GoalCheckIn, goal: Goal) {
        self.id = checkIn.id
        self.goalId = goal.id
        self.goalTitle = goal.title
        self.goalType = goal.goalType
        self.checkIn = checkIn
    }
}

// MARK: - ReflectionFilter

private enum ReflectionFilter: String, CaseIterable, Hashable {
    case all = "All"
    case northStar = "North Star"
    case pillars = "Pillars"
    case goals = "Goals"

    var icon: String {
        switch self {
        case .all: "circle.grid.2x2.fill"
        case .northStar: "crown.fill"
        case .pillars: "star.fill"
        case .goals: "target"
        }
    }
}

// MARK: - ReflectionsView

/// Chronological journal of reflection-shaped check-ins (those with an
/// `alignmentRating`, blockers, commitments, or a prompt answer).
/// Read-only for now — editing reflections happens via the CheckInSheet
/// on the parent goal.
struct ReflectionsView: View {
    @State private var data: AppData = .empty
    /// Cached list of reflection-shaped check-ins. Rebuilt on loadData so
    /// the view body doesn't re-walk all goals × checkIns × sort per render.
    @State private var allReflections: [ReflectionEntry] = []
    /// Cached "You've reflected N times across M weeks." string, rebuilt
    /// in loadData so the header doesn't re-bucket ISO-weeks per render.
    @State private var streakText: String?
    @State private var filter: ReflectionFilter = .all
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                filterPicker
                entries
            }
            .padding()
            .readContainerWidth { containerWidth = $0 }
        }
        .background(Color.bg)
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
    }

    // MARK: Data

    private func loadData() async {
        let loaded = await DataStore.shared.getData()
        var entries: [ReflectionEntry] = []
        for goal in loaded.goals {
            for c in goal.checkIns where c.isReflection {
                entries.append(ReflectionEntry(checkIn: c, goal: goal))
            }
        }
        entries.sort { $0.checkIn.date > $1.checkIn.date }
        data = loaded
        allReflections = entries
        streakText = Self.buildStreakText(from: entries)
    }

    /// "You've reflected 23 times across 21 weeks." — pre-computed in
    /// loadData so the view body doesn't re-bucket ISO-weeks per render.
    private static func buildStreakText(from entries: [ReflectionEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let count = entries.count
        let weekAnchors: Set<Date> = Set(entries.compactMap { entry in
            guard let date = DateFormatting.dateFromString(entry.checkIn.date) else { return nil }
            return HabitEngine.startOfWeek(date)
        })
        let weeks = weekAnchors.count
        let timesWord = count == 1 ? "time" : "times"
        let weekWord = weeks == 1 ? "week" : "weeks"
        return "You've reflected \(count) \(timesWord) across \(weeks) \(weekWord)."
    }

    private var filteredEntries: [ReflectionEntry] {
        switch filter {
        case .all: return allReflections
        case .northStar: return allReflections.filter { $0.goalType == .apex }
        case .pillars: return allReflections.filter { $0.goalType == .subApex }
        case .goals: return allReflections.filter { $0.goalType != .apex && $0.goalType != .subApex }
        }
    }

    // MARK: Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Reflections")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(filteredEntries.count)")
                    .font(.headline).monospacedDigit()
                    .foregroundColor(.textMuted)
            }
            if let streakText {
                Text(streakText)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            Text("How you've been thinking about your goals over time. A reflection is a check-in that captures alignment, blockers, and commitments — not just progress.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(ReflectionFilter.allCases, id: \.self) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var entries: some View {
        if filteredEntries.isEmpty {
            emptyState
        } else {
            VStack(spacing: 10) {
                ForEach(filteredEntries) { entry in
                    reflectionCard(entry)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundColor(.textMuted)
            Text("No reflections yet")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("Tap Reflect on your North Star or a life pillar to record how aligned you're feeling and what's in the way.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func reflectionCard(_ entry: ReflectionEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let type = entry.goalType {
                    Image(systemName: type.icon)
                        .font(.caption)
                        .foregroundColor(type == .apex ? .warning : .accentColor)
                }
                Text(entry.goalTitle)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(DateFormatting.displayDate(entry.checkIn.date))
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }

            if let rating = entry.checkIn.alignmentRating {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.caption)
                        .foregroundColor(AlignmentScale.color(for: rating))
                    Text("Aligned \(rating)/10")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(AlignmentScale.color(for: rating))
                    Text("— \(AlignmentScale.label(for: rating))")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
            }

            if let prompt = entry.checkIn.promptAnswered, !prompt.isEmpty {
                Text(prompt)
                    .font(.caption).italic()
                    .foregroundColor(.textSecondary)
            }

            if !entry.checkIn.note.isEmpty {
                Text(entry.checkIn.note)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !entry.checkIn.blockers.isEmpty {
                labeledList(title: "Blockers", items: entry.checkIn.blockers, color: .warning)
            }

            if !entry.checkIn.commitments.isEmpty {
                labeledList(title: "Commitments", items: entry.checkIn.commitments, color: .success)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private func labeledList(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(color)
                .tracking(0.5)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundColor(color)
                    Text(item)
                        .font(.caption)
                        .foregroundColor(.textPrimary)
                    Spacer()
                }
            }
        }
    }

}
