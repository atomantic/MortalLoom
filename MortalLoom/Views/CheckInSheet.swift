import SwiftUI

// MARK: - Check-In Sheet

/// Unified check-in sheet that branches by goal type:
/// - Standard goals: progress slider + milestone checkboxes + note.
/// - Apex / sub-apex lifelong goals: alignment rating + guided prompt +
///   blockers + commitments. Progress is not tracked on lifetime purposes.
///
/// Optional `stagnationSignal` surfaces an in-context prompt banner so
/// users who open a stale goal directly (not via Reports) still get nudged.
struct CheckInSheet: View {
    let goal: Goal
    let allGoals: [Goal]
    let stagnationSignal: StagnationSignal?
    let onSave: (Goal) -> Void
    @Environment(\.dismiss) private var dismiss

    // Standard-goal state
    @State private var progressPct: Double
    @State private var note: String = ""
    @State private var milestoneStates: [UUID: Bool]
    @State private var showStagnationBanner = true

    // Reflection state (lifelong goals). Default 5 ("Mixed") instead of 7
    // so the slider doesn't tell users how they feel before they engage.
    @State private var alignmentRating: Double = 5
    @State private var selectedPrompt: String = ""
    @State private var blockersText: String = ""
    @State private var commitmentsText: String = ""

    // Defer / snooze state.
    @State private var showDeferPicker = false
    @State private var deferDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    init(
        goal: Goal,
        allGoals: [Goal] = [],
        stagnationSignal: StagnationSignal? = nil,
        onSave: @escaping (Goal) -> Void
    ) {
        self.goal = goal
        self.allGoals = allGoals
        self.stagnationSignal = stagnationSignal
        self.onSave = onSave
        _progressPct = State(initialValue: goal.progressPercent)
        _milestoneStates = State(initialValue: Dictionary(uniqueKeysWithValues: goal.milestones.map { ($0.id, $0.completed) }))
    }

    /// Parent chain from the top-level apex down to the goal's direct parent.
    /// Excludes the goal itself. Used to disambiguate repeated titles like
    /// "Finish design" that live under different pillars/apexes.
    private var ancestors: [Goal] {
        guard !allGoals.isEmpty else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: allGoals.map { ($0.id, $0) })
        var chain: [Goal] = []
        var cursor = goal.parentId
        var seen = Set<UUID>()
        while let pid = cursor, !seen.contains(pid), let parent = byId[pid] {
            chain.append(parent)
            seen.insert(pid)
            cursor = parent.parentId
        }
        return chain.reversed()
    }

    private var isLifelong: Bool {
        goal.goalType == .apex || goal.goalType == .subApex
    }

    var body: some View {
        NavigationStack {
            Form {
                if let signal = stagnationSignal, showStagnationBanner {
                    stagnationBanner(signal)
                }
                goalContextHeader
                if isLifelong {
                    reflectionForm
                } else {
                    progressForm
                }
                deferSection
            }
            .macGroupedFormStyle()
            .navigationTitle(isLifelong ? "Reflect" : "Check In")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                // Pre-fill the reflection prompt with the signal's suggested
                // prompt if one was passed in — it's more relevant than a
                // generic rotation when the user is opening a stale goal.
                if isLifelong && selectedPrompt.isEmpty {
                    selectedPrompt = stagnationSignal?.suggestedPrompt
                        ?? ReflectionPrompts.nextPrompt(for: goal)
                }
            }
        }
        .macSheetFrame(minHeight: 560, idealHeight: 680)
    }

    /// Parent chain rendered as `Apex › Sub-apex › Parent` so the user can
    /// disambiguate repeated goal titles across different branches of the
    /// goal tree.
    @ViewBuilder
    private var breadcrumb: some View {
        HStack(spacing: 4) {
            ForEach(Array(ancestors.enumerated()), id: \.element.id) { idx, ancestor in
                Text(ancestor.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if idx < ancestors.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
            }
        }
        .font(.caption2)
        .foregroundColor(.textMuted)
        .accessibilityLabel("In " + ancestors.map(\.title).joined(separator: ", "))
    }

    /// Shows what the user tapped on while they reflect — title, notes (why),
    /// type, category, horizon, target date.
    @ViewBuilder
    private var goalContextHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let type = goal.goalType {
                        GoalsViewHelpers.goalTypeBadge(type)
                        Text(type.label.uppercased())
                            .font(.caption2).fontWeight(.semibold)
                            .tracking(0.6)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    if let cat = goal.category {
                        GoalsViewHelpers.categoryChip(cat)
                    }
                }

                if !ancestors.isEmpty {
                    breadcrumb
                }

                Text(goal.title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !goal.notes.isEmpty {
                    Text(goal.notes)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if goal.horizon != nil || (!isLifelong && goal.targetDate != nil) {
                    HStack(spacing: 10) {
                        if let horizon = goal.horizon {
                            GoalsViewHelpers.horizonChip(horizon)
                        }
                        if !isLifelong, let target = goal.targetDate {
                            Label(DateFormatting.displayDate(target), systemImage: "calendar")
                                .font(.caption2)
                                .foregroundColor(.textMuted)
                        }
                    }
                }

                if let until = goal.deferredUntil, goal.isDeferred() {
                    Label("Snoozed until \(DateFormatting.displayDate(until))",
                          systemImage: "zzz")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: Defer / snooze

    /// Lets the user push a goal out to a future date. While deferred, the
    /// goal stops generating check-in reminders, stagnation signals, and
    /// slippage warnings. It resumes automatically on the chosen date — no
    /// need to manually unpause.
    @ViewBuilder
    private var deferSection: some View {
        Section {
            if goal.isDeferred(), let until = goal.deferredUntil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "zzz")
                            .foregroundColor(.accentColor)
                        Text("Snoozed until \(DateFormatting.displayDate(until))")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                    }
                    Text("No reminders, stagnation signals, or slippage warnings will fire for this goal until that date.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(role: .destructive) {
                        clearDefer()
                    } label: {
                        Label("Resume now", systemImage: "play.circle")
                    }
                }
            } else if showDeferPicker {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker(
                        "Resume on",
                        selection: $deferDate,
                        in: deferMinDate...,
                        displayedComponents: .date
                    )
                    HStack {
                        Button("Cancel") { showDeferPicker = false }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button {
                            commitDefer()
                        } label: {
                            Label("Snooze", systemImage: "zzz")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button {
                    showDeferPicker = true
                } label: {
                    Label("Snooze until later…", systemImage: "zzz")
                }
            }
        } header: {
            Text("Defer")
        } footer: {
            if !goal.isDeferred() && !showDeferPicker {
                Text("Can't act on this goal yet? Push it out to a specific date.")
                    .font(.caption2)
            }
        }
    }

    private var deferMinDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private func commitDefer() {
        var updated = goal
        updated.deferredUntil = DateFormatting.dateString(deferDate)
        onSave(updated)
        dismiss()
    }

    private func clearDefer() {
        var updated = goal
        updated.deferredUntil = nil
        onSave(updated)
        dismiss()
    }

    /// Dismissible card shown at the top of the sheet when the user opened
    /// this goal via a stagnation signal. Explains *why* the goal needs
    /// attention and surfaces the suggested prompt inline.
    @ViewBuilder
    private func stagnationBanner(_ signal: StagnationSignal) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: signal.severity.iconName)
                        .foregroundColor(signal.severity.tintColor)
                    Text(signal.title)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(signal.severity.tintColor)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                    Button {
                        withAnimation { showStagnationBanner = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                Text(signal.detail)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !signal.suggestedPrompt.isEmpty {
                    Text(signal.suggestedPrompt)
                        .font(.caption).italic()
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                // Acknowledge without checking in (goal-level signals only —
                // see StagnationSignal.isGoalLevel).
                if signal.isGoalLevel {
                    Button {
                        resolveSignal(signal)
                    } label: {
                        Label("Mark resolved", systemImage: "checkmark.circle")
                            .font(.caption).fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(signal.severity.tintColor)
                    .padding(.top, 4)
                }
            }
            .listRowBackground(signal.severity.tintColor.opacity(0.08))
        }
    }

    /// Acknowledge a stagnation signal without logging a check-in: record it as
    /// resolved at its current severity and dismiss. StagnationEngine keeps it
    /// hidden until it escalates further (see `Goal.markSignalResolved`).
    private func resolveSignal(_ signal: StagnationSignal) {
        var updated = goal
        updated.markSignalResolved(signal)
        onSave(updated)
        dismiss()
    }

    // MARK: Standard-goal form

    @ViewBuilder
    private var progressForm: some View {
        Section("Progress") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress: \(Int(progressPct))%")
                        .font(.headline)
                    Spacer()
                    if progressPct > goal.progressPercent {
                        Text("+\(Int(progressPct - goal.progressPercent))%")
                            .font(.caption).foregroundColor(.success)
                    }
                }
                Slider(value: $progressPct, in: 0...100, step: 5)
            }
        }

        if !goal.milestones.isEmpty {
            Section("Milestones") {
                ForEach(goal.milestones) { milestone in
                    Button {
                        milestoneStates[milestone.id]?.toggle()
                        updateProgressFromMilestones()
                    } label: {
                        HStack {
                            Image(systemName: milestoneStates[milestone.id] == true ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(milestoneStates[milestone.id] == true ? .success : .textMuted)
                            Text(milestone.title)
                                .foregroundColor(.textPrimary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Section("Note") {
            TextField("What did you work on?", text: $note, axis: .vertical)
                .lineLimit(2...4)
        }

        if goal.checkIns.count > 1 {
            Section("Recent Check-ins") {
                ForEach(goal.checkIns.suffix(5).reversed()) { checkIn in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(DateFormatting.displayDate(checkIn.date))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Text("\(Int(checkIn.progressPct))%")
                                .font(.caption).fontWeight(.medium)
                                .foregroundColor(.textPrimary)
                        }
                        if !checkIn.note.isEmpty {
                            Text(checkIn.note)
                                .font(.caption2)
                                .foregroundColor(.textMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: Reflection form (lifelong goals)

    @ViewBuilder
    private var reflectionForm: some View {
        Section("How aligned are you feeling?") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Int(alignmentRating))/10")
                        .font(.title2).fontWeight(.bold)
                        .monospacedDigit()
                    Spacer()
                    Text(AlignmentScale.label(for: Int(alignmentRating)))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                Slider(value: $alignmentRating, in: 1...10, step: 1)
            }
        }

        Section("Guided prompt") {
            Text(selectedPrompt)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
            TextField("Your answer", text: $note, axis: .vertical)
                .lineLimit(3...6)
            Button {
                rotatePrompt()
            } label: {
                Label("Different prompt", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
        }

        Section {
            TextField("One blocker per line", text: $blockersText, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("What's holding you back?")
        } footer: {
            Text("Each line becomes a separate entry.")
                .font(.caption2)
        }

        Section {
            TextField("One commitment per line", text: $commitmentsText, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("What will you commit to this period?")
        }

        let reflections = goal.checkIns.filter { $0.isReflection }
        if !reflections.isEmpty {
            Section("Recent Reflections") {
                ForEach(reflections.suffix(3).reversed()) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(DateFormatting.displayDate(c.date))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Spacer()
                            if let rating = c.alignmentRating {
                                Text("\(rating)/10")
                                    .font(.caption).fontWeight(.medium)
                                    .monospacedDigit()
                                    .foregroundColor(.textPrimary)
                            }
                        }
                        if !c.note.isEmpty {
                            Text(c.note)
                                .font(.caption2)
                                .foregroundColor(.textMuted)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func rotatePrompt() {
        selectedPrompt = ReflectionPrompts.nextPrompt(for: goal, excluding: selectedPrompt)
    }

    // MARK: Save

    private func updateProgressFromMilestones() {
        let total = goal.milestones.count
        guard total > 0 else { return }
        let done = milestoneStates.values.filter { $0 }.count
        progressPct = Double(done) / Double(total) * 100
    }

    private func save() {
        var updated = goal
        // A check-in is the canonical "I've re-engaged with this goal" action,
        // so clear any previously acknowledged ("resolved") stagnation signals.
        // A future stagnation cycle should surface normally rather than stay
        // suppressed by a stale resolution.
        updated.resolvedSignals = []

        if isLifelong {
            let blockersList = blockersText
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let commitmentsList = commitmentsText
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            updated.checkIns.append(GoalCheckIn(
                progressPct: 0,
                note: note.trimmingCharacters(in: .whitespaces),
                alignmentRating: Int(alignmentRating),
                blockers: blockersList,
                commitments: commitmentsList,
                promptAnswered: selectedPrompt
            ))
        } else {
            for i in updated.milestones.indices {
                let wasCompleted = updated.milestones[i].completed
                let nowCompleted = milestoneStates[updated.milestones[i].id] ?? wasCompleted
                updated.milestones[i].completed = nowCompleted
                if nowCompleted && !wasCompleted {
                    updated.milestones[i].completedDate = DateFormatting.todayString()
                } else if !nowCompleted {
                    updated.milestones[i].completedDate = nil
                }
            }

            updated.checkIns.append(GoalCheckIn(
                progressPct: progressPct,
                note: note.trimmingCharacters(in: .whitespaces)
            ))

            if progressPct >= 100 && updated.status == .active {
                updated.status = .completed
                updated.completedDate = DateFormatting.todayString()
            }
        }

        onSave(updated)
        dismiss()
    }
}
