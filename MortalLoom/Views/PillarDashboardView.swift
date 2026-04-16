import SwiftUI

// MARK: - PillarDashboardView

/// Drill-in detail for a single life pillar (sub-apex goal). Shows the pillar's
/// own header, current sub-alignment score, linked standard goals with progress,
/// linked habits with streaks, and recent reflections. Opened by tapping a
/// sub-apex in the Goals tree.
struct PillarDashboardView: View {
    let pillar: Goal
    let allGoals: [Goal]
    let allHabits: [Habit]
    let onEditGoal: (Goal) -> Void
    let onReflect: (Goal) -> Void
    let onEditHabit: (Habit) -> Void

    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    @State private var timeAllocation: TimeAllocationEngine.Allocation?
    @State private var calendarAvailable = false
    @State private var habitStats: [UUID: HabitStats] = [:]

    private var isWide: Bool { containerWidth >= Layout.wideThreshold }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                alignmentCard
                if timeAllocation != nil { timeAllocatedCard }
                supportingGoalsCard
                habitsCard
                reflectionsCard
            }
            .padding()
            .readContainerWidth { containerWidth = $0 }
        }
        .background(Color.bg)
        .task {
            computeHabitStats()
            await loadTimeAllocation()
        }
        .navigationTitle(pillar.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Time allocation loader

    /// Pulls MortalLoom-tagged calendar events from the last 30 days and
    /// rolls them up through the goal hierarchy. Runs on the main actor
    /// because CalendarService is @MainActor.
    /// Precompute streak/hit-rate for all linked habits in one pass so the
    /// habit-row renderer can look them up instead of recomputing per frame.
    private func computeHabitStats() {
        let now = Date()
        var stats: [UUID: HabitStats] = [:]
        for h in linkedHabits {
            stats[h.id] = HabitStats(
                streak: HabitEngine.currentStreak(h, now: now),
                hitRate30d: HabitEngine.targetHitRate(h, windowDays: 30, now: now),
                todayCount: HabitEngine.completionsInPeriod(h, containing: now)
            )
        }
        habitStats = stats
    }

    @MainActor
    private func loadTimeAllocation() async {
        #if os(iOS)
        let service = CalendarService.shared
        guard service.isAuthorized else {
            calendarAvailable = false
            timeAllocation = nil
            return
        }
        calendarAvailable = true
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let events = service.tagged(from: thirtyDaysAgo, to: now)
        timeAllocation = TimeAllocationEngine.allocate(goals: allGoals, events: events)
        #else
        calendarAvailable = false
        timeAllocation = nil
        #endif
    }

    // MARK: Computed

    private var supportingGoals: [Goal] {
        allGoals.filter { $0.parentId == pillar.id && $0.status == .active }
    }

    private var linkedHabits: [Habit] {
        let descendantIds: Set<UUID> = Set([pillar.id] + GoalEngine.activeDescendants(of: pillar, in: allGoals).map(\.id))
        return allHabits.filter { h in
            guard h.isActive, let parent = h.parentGoalId else { return false }
            return descendantIds.contains(parent)
        }
    }

    private var subAlignment: Double? {
        GoalEngine.alignmentScore(for: pillar, in: allGoals, habits: allHabits)
    }

    private var recentReflections: [GoalCheckIn] {
        let pillarReflections = pillar.checkIns.filter { $0.isReflection }
        return Array(pillarReflections.suffix(5).reversed())
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("LIFE PILLAR")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.accentColor)
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
                Button {
                    onReflect(pillar)
                } label: {
                    Label("Reflect", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Text(pillar.title)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)

            if !pillar.notes.isEmpty {
                Text(pillar.notes)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }

            HStack(spacing: 12) {
                if let cat = pillar.category {
                    Label(cat.label, systemImage: cat.icon)
                        .font(.caption)
                        .foregroundColor(cat.swiftUIColor)
                }
                Label("\(supportingGoals.count) sub-goal\(supportingGoals.count == 1 ? "" : "s")",
                      systemImage: "target")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                Label("\(linkedHabits.count) habit\(linkedHabits.count == 1 ? "" : "s")",
                      systemImage: "repeat.circle")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(fill: .accentColor.opacity(0.06), border: .accentColor.opacity(0.2))
    }

    // MARK: Alignment

    private var alignmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "PILLAR ALIGNMENT")
            if let score = subAlignment {
                HStack {
                    Text(String(format: "%.0f%%", score))
                        .font(.title).fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.accentColor)
                    Spacer()
                    Text(AlignmentScale.label(forPercent: score))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bgInput)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient.proBrand)
                            .frame(width: geo.size.width * min(1, score / 100), height: 8)
                    }
                }
                .frame(height: 8)
                Text("70% average progress across concrete goals + 30% habit streak health.")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            } else {
                Text("Add concrete goals or linked habits to this pillar to start tracking alignment.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Time allocated

    @ViewBuilder
    private var timeAllocatedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "TIME ALLOCATED (30 DAYS)")
            if let allocation = timeAllocation {
                let pillarMinutes = allocation.minutesByAncestor[pillar.id] ?? 0
                if pillarMinutes == 0 {
                    Text("No calendar work blocks tagged to this pillar in the last 30 days.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text("Tap a supporting goal → Edit → Schedule on Calendar to start tracking real time investment.")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(TimeAllocationEngine.formatMinutes(pillarMinutes))
                            .font(.title2).fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.accentColor)
                        Text("scheduled toward this pillar")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    // Per-supporting-goal breakdown
                    let rows = supportingGoals.compactMap { g -> (Goal, Int)? in
                        guard let minutes = allocation.minutesByAncestor[g.id], minutes > 0 else { return nil }
                        return (g, minutes)
                    }.sorted { $0.1 > $1.1 }
                    if !rows.isEmpty {
                        Divider().padding(.vertical, 4)
                        ForEach(rows, id: \.0.id) { (g, minutes) in
                            HStack {
                                Text(g.title)
                                    .font(.caption)
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(TimeAllocationEngine.formatMinutes(minutes))
                                    .font(.caption).monospacedDigit()
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Supporting goals

    private var supportingGoalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "SUPPORTING GOALS")
            if supportingGoals.isEmpty {
                Text("No concrete goals feed into this pillar yet.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(supportingGoals) { goal in
                        supportingGoalRow(goal)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func supportingGoalRow(_ goal: Goal) -> some View {
        Button {
            onEditGoal(goal)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let iconName = goal.goalType?.icon {
                        Image(systemName: iconName)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    Text(goal.title)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(goal.progressPercent))%")
                        .font(.caption).monospacedDigit()
                        .foregroundColor(.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.bgInput)
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * min(1, goal.progressPercent / 100), height: 5)
                    }
                }
                .frame(height: 5)
            }
            .padding(8)
            .background(Color.bgInput.opacity(0.4))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: Habits

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "LINKED HABITS")
            if linkedHabits.isEmpty {
                Text("No habits linked to this pillar yet. Daily habits like writing, practicing, or meditating can power alignment here.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(linkedHabits) { habit in
                        habitRow(habit)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func habitRow(_ habit: Habit) -> some View {
        let stats = habitStats[habit.id] ?? HabitStats(streak: 0, hitRate30d: 0, todayCount: 0)
        let streak = stats.streak
        let hit = stats.hitRate30d
        return Button {
            onEditHabit(habit)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(habit.color.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: habit.icon)
                        .foregroundColor(habit.color)
                        .font(.caption)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text(habit.cadence.label)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(streak > 0 ? .orange : .textMuted)
                        .font(.caption2)
                    Text("\(streak)")
                        .font(.caption).monospacedDigit()
                        .foregroundColor(.textPrimary)
                }
                Text("\(Int(hit))%")
                    .font(.caption).monospacedDigit()
                    .foregroundColor(.accentColor)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Reflections

    private var reflectionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "RECENT REFLECTIONS")
            if recentReflections.isEmpty {
                Text("No reflections yet. Tap Reflect above to record how aligned this pillar feels right now.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentReflections) { c in
                        reflectionRow(c)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func reflectionRow(_ c: GoalCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(DateFormatting.displayDate(c.date))
                    .font(.caption2)
                    .foregroundColor(.textMuted)
                Spacer()
                if let rating = c.alignmentRating {
                    Text("\(rating)/10")
                        .font(.caption).monospacedDigit()
                        .foregroundColor(.textPrimary)
                }
            }
            if !c.note.isEmpty {
                Text(c.note)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(8)
        .background(Color.bgInput.opacity(0.4))
        .cornerRadius(8)
    }
}
