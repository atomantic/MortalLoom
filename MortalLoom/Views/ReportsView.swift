import SwiftUI
import Charts

// MARK: - ReportsView (MVP)

/// Goal-system analytics. The MVP answers three questions:
///
/// 1. How has my alignment trended? — derived from reflection ratings +
///    active standard-goal progress, sampled weekly.
/// 2. What's stalling? — StagnationEngine signals, grouped by severity.
/// 3. Which pillar is strongest/weakest? — per-pillar alignment breakdown.
///
/// Everything is computed on-demand from current state. Future phases may
/// snapshot alignment daily for faster historical queries.
struct ReportsView: View {
    @State private var data: AppData = .empty
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    @State private var stagnationSignals: [StagnationSignal] = []
    /// Pre-computed 12-week alignment trend — cached in loadData so the
    /// chart + week-over-week delta don't recompute per render.
    @State private var trendPoints: [AlignmentPoint] = []
    /// Pre-computed per-pillar alignment so the pillar ForEach doesn't
    /// walk the tree on each render.
    @State private var pillarAlignments: [UUID: Double] = [:]
    /// Pre-computed per-habit stats for the Habit Streaks card.
    @State private var habitStats: [UUID: HabitStats] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                alignmentTrendCard
                stagnationCard
                pillarBreakdownCard
                habitHealthCard
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
        data = loaded
        stagnationSignals = StagnationEngine.signals(
            goals: loaded.goals,
            habits: loaded.habits
        )
        // Precompute trend points + pillar alignments + habit stats once so
        // the render path doesn't re-walk the goal tree per row.
        trendPoints = buildTrendPoints(from: loaded)
        var alignments: [UUID: Double] = [:]
        for pillar in loaded.goals where pillar.goalType == .subApex && pillar.status == .active {
            if let score = GoalEngine.alignmentScore(for: pillar, in: loaded.goals) {
                alignments[pillar.id] = score
            }
        }
        pillarAlignments = alignments
        let now = Date()
        var stats: [UUID: HabitStats] = [:]
        for h in loaded.habits where h.isActive {
            stats[h.id] = HabitStats(
                streak: HabitEngine.currentStreak(h, now: now),
                hitRate30d: HabitEngine.targetHitRate(h, windowDays: 30, now: now),
                todayCount: HabitEngine.completionsInPeriod(h, containing: now)
            )
        }
        habitStats = stats
    }

    private var apexGoal: Goal? { data.goals.activeApex }

    private var pillars: [Goal] {
        data.goals.filter { $0.goalType == .subApex && $0.status == .active }
    }

    // MARK: Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Reports")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            Text("Your alignment, what's stalling, and which pillars are carrying the load.")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Alignment trend

    private var alignmentTrendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "ALIGNMENT TREND")

            if !trendPoints.isEmpty {
                let points = trendPoints
                Chart(points) { point in
                    LineMark(
                        x: .value("Week", point.date),
                        y: .value("Alignment", point.score)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient.proBrand)
                    AreaMark(
                        x: .value("Week", point.date),
                        y: .value("Alignment", point.score)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient.proBrandSubtleDiagonal)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)

                HStack {
                    if let latest = points.last {
                        Text("Current: \(Int(latest.score))%")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    if let delta = alignmentWeekOverWeekDelta() {
                        let sign = delta >= 0 ? "+" : ""
                        Text("\(sign)\(Int(delta))% vs last week")
                            .font(.caption)
                            .foregroundColor(delta >= 0 ? .success : .danger)
                    }
                }
            } else {
                emptyInline(
                    icon: "chart.line.uptrend.xyaxis",
                    text: "Add supporting goals and reflect on your North Star to start building an alignment history."
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Stagnation

    private var stagnationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "ATTENTION NEEDED")
                Spacer()
                Text("\(stagnationSignals.count)")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.textMuted)
            }

            if stagnationSignals.isEmpty {
                emptyInline(
                    icon: "checkmark.seal.fill",
                    text: "Nothing is stalling right now. Keep going."
                )
            } else {
                ForEach(stagnationSignals) { signal in
                    stagnationRow(signal)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func stagnationRow(_ signal: StagnationSignal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: severityIcon(signal.severity))
                .foregroundColor(severityColor(signal.severity))
                .font(.body)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                Text(signal.detail)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(signal.suggestedPrompt)
                    .font(.caption2).italic()
                    .foregroundColor(.textMuted)
                    .padding(.top, 2)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func severityIcon(_ s: StagnationSeverity) -> String {
        switch s {
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle"
        case .alert: "exclamationmark.octagon.fill"
        }
    }

    private func severityColor(_ s: StagnationSeverity) -> Color {
        switch s {
        case .info: .accentColor
        case .warn: .warning
        case .alert: .danger
        }
    }

    // MARK: Pillar breakdown

    private var pillarBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "PILLAR ALIGNMENT")

            if pillars.isEmpty {
                emptyInline(
                    icon: "star",
                    text: "Add life pillars under your North Star to see per-pillar alignment."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(pillars) { pillar in
                        pillarBar(pillar)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func pillarBar(_ pillar: Goal) -> some View {
        let score = pillarAlignments[pillar.id]

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pillar.title)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                Spacer()
                if let score {
                    Text("\(Int(score))%")
                        .font(.caption).monospacedDigit()
                        .foregroundColor(.accentColor)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.bgInput)
                        .frame(height: 6)
                    if let score {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient.proBrand)
                            .frame(width: geo.size.width * min(1, score / 100), height: 6)
                    }
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: Habit health

    private var habitHealthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "HABIT STREAKS")

            let active = data.habits.filter { $0.isActive }
            if active.isEmpty {
                emptyInline(
                    icon: "repeat.circle",
                    text: "Add habits to track daily or weekly actions that move you toward your goals."
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(active) { habit in
                        habitStreakRow(habit)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func habitStreakRow(_ habit: Habit) -> some View {
        let stats = habitStats[habit.id] ?? HabitStats(streak: 0, hitRate30d: 0, todayCount: 0)
        let streak = stats.streak
        let hitRate = stats.hitRate30d

        return HStack(spacing: 10) {
            Image(systemName: habit.icon)
                .foregroundColor(habit.color)
                .frame(width: 24)
            Text(habit.name)
                .font(.caption).fontWeight(.medium)
                .foregroundColor(.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(streak > 0 ? .orange : .textMuted)
                    .font(.caption2)
                Text("\(streak)")
                    .font(.caption).monospacedDigit()
                    .foregroundColor(.textPrimary)
            }
            Text("\(Int(hitRate))%")
                .font(.caption).monospacedDigit()
                .foregroundColor(.accentColor)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: Helpers

    private func emptyInline(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.textMuted)
            Text(text)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: Alignment trend math

    private struct AlignmentPoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: Double
    }

    /// Build a per-week alignment history from the current `AppData`
    /// snapshot. 70% goal progress + 30% reflection rating per week.
    /// Called once per loadData and cached in `trendPoints`.
    private func buildTrendPoints(from data: AppData) -> [AlignmentPoint] {
        guard let apex = data.goals.activeApex else { return [] }
        let leaves = GoalEngine.standardDescendants(of: apex, in: data.goals)
        let hasReflection = apex.checkIns.contains { $0.isReflection }
        guard !leaves.isEmpty || hasReflection else { return [] }

        let now = Date()
        let calendar = Calendar.current
        let weeks = 12
        var points: [AlignmentPoint] = []

        for weekOffset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekDate = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now) else { continue }
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekDate)) ?? weekDate
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekDate

            let progressAvg = averageProgressFromCheckIns(leaves, through: weekEnd)
            let ratingAvg = averageReflectionRating(apex: apex, from: weekStart, to: weekEnd)

            let combined: Double
            if let p = progressAvg, let r = ratingAvg {
                combined = p * 0.7 + (r * 10) * 0.3
            } else if let p = progressAvg {
                combined = p
            } else if let r = ratingAvg {
                combined = r * 10
            } else {
                continue
            }
            points.append(AlignmentPoint(date: weekStart, score: max(0, min(100, combined))))
        }
        return points
    }

    /// Last check-in on or before `date` for each goal, averaged. A rough
    /// approximation of historical alignment without daily snapshotting.
    private func averageProgressFromCheckIns(_ goals: [Goal], through date: Date) -> Double? {
        guard !goals.isEmpty else { return nil }
        let dateStr = DateFormatting.dateString(date)
        var total = 0.0
        var count = 0
        for g in goals {
            guard let last = g.checkIns.last(where: { $0.date <= dateStr }) else { continue }
            total += last.progressPct
            count += 1
        }
        return count > 0 ? total / Double(count) : nil
    }

    private func averageReflectionRating(apex: Goal, from: Date, to: Date) -> Double? {
        let fromStr = DateFormatting.dateString(from)
        let toStr = DateFormatting.dateString(to)
        let weekRatings = apex.checkIns.compactMap { c -> Double? in
            guard let rating = c.alignmentRating else { return nil }
            guard c.date >= fromStr && c.date < toStr else { return nil }
            return Double(rating)
        }
        guard !weekRatings.isEmpty else { return nil }
        return weekRatings.reduce(0, +) / Double(weekRatings.count)
    }

    private func alignmentWeekOverWeekDelta() -> Double? {
        guard trendPoints.count >= 2 else { return nil }
        return trendPoints[trendPoints.count - 1].score - trendPoints[trendPoints.count - 2].score
    }
}
