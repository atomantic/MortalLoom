import SwiftUI

// MARK: - MonthlyRethinkSheet

/// The monthly rethink is the longer-horizon companion to the Weekly Review.
/// Once a month — surfaced from the Overview only in the closing days of the
/// calendar month — the user walks their goal tree and decides, per node,
/// whether to **Keep**, **Edit**, or **Archive** it. Archiving sets the
/// goal's status to `.abandoned` (the app's existing "let it go" state).
///
/// On finish a single compound reflection `GoalCheckIn` is appended to the
/// North Star summarising the session (kept / edited / archived counts, an
/// optional monthly-prompt answer, and an alignment self-rating), and the
/// completion date is stamped so the card stops surfacing for the month.
struct MonthlyRethinkSheet: View {
    let allGoals: [Goal]
    let habits: [Habit]
    /// Persist a single mutated goal — an inline edit, an archive, or the
    /// apex carrying the compound check-in. Mirrors the single-goal `onSave`
    /// used by the other Overview sheets.
    let onSaveGoal: (Goal) -> Void
    /// Called once the rethink is committed so the caller can refresh.
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Working copy so inline edits/archives are reflected in the tree as the
    /// user goes, without round-tripping through the data store mid-session.
    @State private var workingGoals: [Goal]
    @State private var decisions: [UUID: RethinkDecision] = [:]
    @State private var editingGoal: Goal?
    @State private var selectedPrompt: String = ""
    @State private var answer: String = ""
    // Default 5 ("Mixed") — don't assume how the user feels before they touch
    // the slider. Matches WeeklyReviewSheet.
    @State private var alignmentRating: Double = 5

    init(
        allGoals: [Goal],
        habits: [Habit],
        onSaveGoal: @escaping (Goal) -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.allGoals = allGoals
        self.habits = habits
        self.onSaveGoal = onSaveGoal
        self.onComplete = onComplete
        _workingGoals = State(initialValue: allGoals)
    }

    enum RethinkDecision: Equatable { case keep, archive }

    private struct TreeRow: Identifiable {
        let id: UUID
        let goal: Goal
        let depth: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    Divider()
                    goalTreeSection
                    Divider()
                    reflectionSection
                }
                .padding()
            }
            .background(Color.bg)
            .navigationTitle("Monthly Rethink")
            .inlineNavigationTitle()
            .macSheetFrame()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { finish() }
                        .fontWeight(.semibold)
                        .disabled(workingGoals.activeApex == nil)
                }
            }
            .onAppear {
                if selectedPrompt.isEmpty {
                    selectedPrompt = ReflectionPrompts.nextPrompt(
                        for: workingGoals.activeApex,
                        pool: ReflectionPrompts.monthly
                    )
                }
            }
            .sheet(item: $editingGoal) { goal in
                GoalEditSheet(
                    goal: goal,
                    allGoals: workingGoals,
                    allHabits: habits,
                    onSave: { updated in
                        if let idx = workingGoals.firstIndex(where: { $0.id == updated.id }) {
                            workingGoals[idx] = updated
                        }
                        onSaveGoal(updated)
                    }
                )
            }
        }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Are these still the right goals?")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Walk your goals and decide what to keep, edit, or let go. Then capture one reflection on the month.")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Goal tree

    @ViewBuilder
    private var goalTreeSection: some View {
        let rows = treeRows
        if rows.isEmpty {
            Text("Set a North Star to start your monthly rethink.")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows) { row(for: $0) }
            }
        }
    }

    /// Apex first, then a depth-first walk of active descendants ordered by
    /// priority then title so siblings render stably.
    private var treeRows: [TreeRow] {
        guard let apex = workingGoals.activeApex else { return [] }
        var rows: [TreeRow] = [TreeRow(id: apex.id, goal: apex, depth: 0)]
        func addChildren(of parentId: UUID, depth: Int) {
            let kids = workingGoals
                .filter { $0.parentId == parentId && $0.status == .active }
                .sorted { ($0.priority, $0.title) < ($1.priority, $1.title) }
            for kid in kids {
                rows.append(TreeRow(id: kid.id, goal: kid, depth: depth))
                addChildren(of: kid.id, depth: depth + 1)
            }
        }
        addChildren(of: apex.id, depth: 1)
        return rows
    }

    @ViewBuilder
    private func row(for treeRow: TreeRow) -> some View {
        let goal = treeRow.goal
        let decision = decisions[goal.id] ?? .keep
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: goal.goalType?.icon ?? "circle.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .strikethrough(decision == .archive, color: .warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(goal.goalType?.label ?? "Goal")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                actionChip(label: "Keep", icon: "checkmark", active: decision == .keep, tint: .success) {
                    decisions[goal.id] = .keep
                }
                actionChip(label: "Edit", icon: "pencil", active: false, tint: .accentColor) {
                    editingGoal = goal
                }
                // The North Star anchors the whole tree — archiving it would
                // orphan every pillar and goal beneath it, so it's keep/edit only.
                if goal.goalType != .apex {
                    actionChip(label: "Archive", icon: "archivebox", active: decision == .archive, tint: .warning) {
                        decisions[goal.id] = .archive
                    }
                }
            }
        }
        .padding(.leading, CGFloat(treeRow.depth) * 16)
        .opacity(decision == .archive ? 0.55 : 1)
    }

    private func actionChip(label: String, icon: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption).fontWeight(.medium)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(active ? tint.opacity(0.18) : Color.bgInput)
            .foregroundColor(active ? tint : .textSecondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: Reflection

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedPrompt)
                .font(.headline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(10)

            TextField("Reflect on the month — what changed, what matters now", text: $answer, axis: .vertical)
                .lineLimit(4...10)
                .padding(12)
                .background(Color.bgInput)
                .cornerRadius(10)

            Button {
                selectedPrompt = ReflectionPrompts.nextPrompt(
                    for: workingGoals.activeApex,
                    excluding: selectedPrompt,
                    pool: ReflectionPrompts.monthly
                )
            } label: {
                Label("Give me a different question", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 8) {
                Text("How aligned has this month been, 1–10?")
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                HStack {
                    Text("\(Int(alignmentRating))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.accentColor)
                    Text(AlignmentScale.label(for: Int(alignmentRating)))
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                Slider(value: $alignmentRating, in: 1...10, step: 1)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Finish

    private func finish() {
        guard var apex = workingGoals.activeApex else { return }

        // Apply archive decisions. Use the working copy (which carries any
        // inline edits) as the source of truth, but skip the apex defensively
        // — its chip never offers Archive.
        var archivedCount = 0
        for (goalId, decision) in decisions where decision == .archive {
            guard goalId != apex.id,
                  var goal = workingGoals.first(where: { $0.id == goalId }) else { continue }
            goal.status = .abandoned
            onSaveGoal(goal)
            archivedCount += 1
        }

        let originalById = Dictionary(allGoals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let editedCount = workingGoals.filter { originalById[$0.id] != $0 }.count
        let activeCount = treeRows.count
        let keptCount = max(0, activeCount - archivedCount)

        var summary = "Monthly rethink: kept \(keptCount), edited \(editedCount), archived \(archivedCount)."
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAnswer.isEmpty {
            summary += "\n\n\(trimmedAnswer)"
        }

        apex.checkIns.append(GoalCheckIn(
            progressPct: 0,
            note: summary,
            alignmentRating: Int(alignmentRating),
            promptAnswered: selectedPrompt
        ))
        onSaveGoal(apex)

        MonthlyRethink.recordCompletion()
        onComplete()
        dismiss()
    }
}

// MARK: - MonthlyRethink scheduling helpers

/// Drives when the Overview surfaces the Monthly Rethink card. The card only
/// appears in the closing days of the calendar month, and only until the user
/// completes a rethink for that month — mirroring the WeeklyReview helper.
enum MonthlyRethink {
    static let lastDateKey = "lastMonthlyRethinkDate"
    /// How many days at the end of the month the card is offered.
    static let windowDays = 5

    /// True when `now` falls within the last `windowDays` days of its month.
    static func isInEndOfMonthWindow(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = calendar.component(.day, from: now)
        guard let range = calendar.range(of: .day, in: .month, for: now) else { return false }
        return day > range.count - windowDays
    }

    /// True when a rethink has already been recorded for the calendar month
    /// containing `now`.
    static func isDone(forMonthOf now: Date, lastDate: String?, calendar: Calendar = .current) -> Bool {
        guard let lastDate, let last = DateFormatting.dateFromString(lastDate) else { return false }
        return calendar.isDate(last, equalTo: now, toGranularity: .month)
    }

    /// Pure due check: inside the end-of-month window AND not yet done this
    /// month. Takes `lastDate` explicitly so it's testable without UserDefaults.
    static func isDue(now: Date = Date(), lastDate: String?, calendar: Calendar = .current) -> Bool {
        isInEndOfMonthWindow(now: now, calendar: calendar)
            && !isDone(forMonthOf: now, lastDate: lastDate, calendar: calendar)
    }

    /// Persisted date ("YYYY-MM-DD") of the last completed rethink.
    static var lastDate: String? {
        UserDefaults.standard.string(forKey: lastDateKey)
    }

    /// Convenience reading the persisted date — used by the Overview card.
    static var isDueNow: Bool {
        isDue(now: Date(), lastDate: lastDate)
    }

    static func recordCompletion(date: String = DateFormatting.todayString()) {
        UserDefaults.standard.set(date, forKey: lastDateKey)
    }
}
