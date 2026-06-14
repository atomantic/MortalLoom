import SwiftUI

// MARK: - Goal Edit Sheet

struct GoalEditSheet: View {
    let goal: Goal?
    let allGoals: [Goal]
    /// Active habits, used so the stagnation-muting section reflects
    /// habit-based signals (missed-cadence nags) and not just goal-only
    /// signals. Defaults to empty for call sites that don't surface the
    /// muting section (new-goal flows, where `isEditingExisting` is false).
    let allHabits: [Habit]
    let onSave: (Goal) -> Void
    let onDelete: (() -> Void)?
    let onAddChild: ((Goal) -> Void)?
    /// Non-nil when this sheet was opened to accept a `GenomeAction` via the
    /// `.goalTemplate` bridge. The banner appears at the top, the evidence
    /// is attached on save, and the sheet treats this as a "new" form (no
    /// archive/delete sections, "Suggested Goal" title) regardless of
    /// whether `goal` is nil. Mirrors `HabitEditSheet.prefillEvidence`.
    let prefillEvidence: GeneticEvidence?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var priority: GoalPriority
    @State private var checkInInterval: Int
    @State private var milestoneTexts: [MilestoneRow]
    @State private var parentId: UUID?
    @State private var horizon: GoalHorizon?
    @State private var category: GoalCategory?
    @State private var goalType: GoalType?
    @State private var showDeleteConfirm = false
    #if os(iOS)
    @State private var showCalendarScheduler = false
    @State private var scheduleMessage: String?
    #endif
    @State private var showGoalHint = false
    @State private var showingAddChild = false
    @State private var mutedSignals: Set<String> = []

    private struct MilestoneRow: Identifiable {
        let id: UUID
        var text: String
        var completed: Bool
    }

    init(
        goal: Goal?,
        allGoals: [Goal] = [],
        allHabits: [Habit] = [],
        defaultGoalType: GoalType? = nil,
        defaultHorizon: GoalHorizon? = nil,
        defaultPriority: GoalPriority? = nil,
        defaultParentId: UUID? = nil,
        defaultCategory: GoalCategory? = nil,
        prefillEvidence: GeneticEvidence? = nil,
        onSave: @escaping (Goal) -> Void,
        onDelete: (() -> Void)? = nil,
        onAddChild: ((Goal) -> Void)? = nil
    ) {
        self.goal = goal
        self.allGoals = allGoals
        self.allHabits = allHabits
        self.prefillEvidence = prefillEvidence
        self.onSave = onSave
        self.onDelete = onDelete
        self.onAddChild = onAddChild
        let g = goal
        _title = State(initialValue: g?.title ?? "")
        _notes = State(initialValue: g?.notes ?? "")
        _hasTargetDate = State(initialValue: g?.targetDate != nil)
        _targetDate = State(initialValue: {
            if let t = g?.targetDate { return DateFormatting.dateFromString(t) ?? Date() }
            return Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        }())
        _priority = State(initialValue: g?.priority ?? defaultPriority ?? .medium)
        // Existing goals keep their saved cadence; new goals inherit the
        // global check-in default (Settings → Reflection Cadence).
        _checkInInterval = State(initialValue: g?.checkInIntervalDays
            ?? NotificationService.defaultCheckInInterval)
        _milestoneTexts = State(initialValue: g?.milestones.map {
            MilestoneRow(id: $0.id, text: $0.title, completed: $0.completed)
        } ?? [])
        // For new non-apex goals, default parent to the user's apex if one
        // exists and no explicit default was passed. Top-level standard and
        // sub-apex goals contribute nothing to the alignment tree, so landing
        // at apex-root is almost always what the user wants.
        let resolvedType = g?.goalType ?? defaultGoalType ?? .standard
        let resolvedParent: UUID? = {
            if let existing = g?.parentId { return existing }
            if let explicit = defaultParentId { return explicit }
            if resolvedType != .apex, let inferredApex = allGoals.first(where: { $0.goalType == .apex && $0.status == .active }) {
                return inferredApex.id
            }
            return nil
        }()
        _parentId = State(initialValue: resolvedParent)
        // Apex is always lifetime; sub-apex defaults to lifetime but stays editable for standard goals.
        let resolvedHorizon: GoalHorizon? = (resolvedType == .apex) ? .lifetime : (g?.horizon ?? defaultHorizon)
        _horizon = State(initialValue: resolvedHorizon)
        _category = State(initialValue: g?.category ?? defaultCategory)
        _goalType = State(initialValue: resolvedType)
        _mutedSignals = State(initialValue: Set(g?.mutedSignals ?? []))
    }

    /// Apex (North Star) and Sub-Apex (Life Pillar) goals are lifetime purposes:
    /// no end date, no progress %, no calendar work blocks, no text milestones.
    /// Their structure comes from supporting child goals in the tree.
    private var isLifelong: Bool {
        goalType == .apex || goalType == .subApex
    }

    /// True when editing an already-saved goal (vs a new one — even one
    /// prefilled from a genome action). Mirrors `HabitEditSheet`.
    private var isEditingExisting: Bool { goal != nil && prefillEvidence == nil }

    /// Provenance for the "🧬 Suggested by your DNA" banner. Prefer the
    /// in-flight prefill payload over the saved goal's evidence (they refer
    /// to the same finding and the prefill text is canonical).
    private var displayEvidence: GeneticEvidence? {
        prefillEvidence ?? goal?.geneticEvidence
    }

    /// Active supporting (child) goals for the goal being edited.
    private var supportingGoals: [Goal] {
        guard let g = goal else { return [] }
        return allGoals.filter { $0.parentId == g.id && $0.status == .active }
    }

    /// Placeholder text and hint example adapt to the selected goal type.
    private var goalTitlePlaceholder: String {
        switch goalType {
        case .apex: return "e.g. Live Healthy for as Long as Possible"
        case .subApex: return "e.g. Build strong physical fitness"
        case .standard, .none: return "What do you want to achieve?"
        }
    }

    private var goalHintExample: String {
        switch goalType {
        case .apex:
            return "A North Star is your single biggest life ambition — broad and lifelong. Examples:\n\n• Live healthy for as long as possible\n• Leave a lasting creative legacy\n• Raise a loving, resilient family"
        case .subApex:
            return "A Life Pillar is a major area that supports your North Star. Examples:\n\n• Build strong physical fitness\n• Achieve financial independence\n• Develop deep expertise in my craft"
        case .standard, .none:
            return "A goal is something concrete you want to achieve by a target date. Examples:\n\n• Run a half-marathon this fall\n• Publish my first novel\n• Save $20,000 for a down payment"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let evidence = displayEvidence {
                    Section {
                        GeneticEvidenceBanner(evidence: evidence, dismiss: dismiss)
                    }
                }

                Section {
                    TextField("Title", text: $title, prompt: Text(goalTitlePlaceholder))
                    if title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Give this goal a title to save.")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    HStack(spacing: 6) {
                        Text("Goal")
                        Button {
                            showGoalHint.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Goal examples")
                        .popover(isPresented: $showGoalHint, arrowEdge: .bottom) {
                            Text(goalHintExample)
                                .font(.footnote)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding()
                                .frame(width: 300, alignment: .leading)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }

                Section("Classification") {
                    // Type is required — an untyped goal can't participate in
                    // the hierarchy or alignment scoring. Default is `.standard`.
                    Picker("Type", selection: $goalType) {
                        ForEach(GoalType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.icon).tag(GoalType?.some(t))
                        }
                    }
                    .onChange(of: goalType) { _, newValue in
                        // North Star is always a lifetime purpose.
                        if newValue == .apex { horizon = .lifetime }
                    }

                    Picker("Category", selection: $category) {
                        Text("None").tag(GoalCategory?.none)
                        ForEach(GoalCategory.allCases, id: \.self) { c in
                            Label(c.label, systemImage: c.icon).tag(GoalCategory?.some(c))
                        }
                    }

                    if goalType == .apex {
                        HStack {
                            Text("Horizon")
                            Spacer()
                            Text("Lifetime").foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Horizon", selection: $horizon) {
                            Text("None").tag(GoalHorizon?.none)
                            ForEach(GoalHorizon.allCases, id: \.self) { h in
                                Text(h.label).tag(GoalHorizon?.some(h))
                            }
                        }
                    }

                    Picker("Parent Goal", selection: $parentId) {
                        Text("None (top-level)").tag(UUID?.none)
                        ForEach(parentCandidates, id: \.id) { g in
                            Text(g.title).tag(UUID?.some(g.id))
                        }
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(GoalPriority.allCases, id: \.self) { p in
                            Text(p.rawValue.capitalized).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if !isLifelong {
                    Section("Deadline") {
                        Toggle("Set target date", isOn: $hasTargetDate)
                        if hasTargetDate {
                            DatePicker("Target", selection: $targetDate, displayedComponents: .date)
                        }
                    }

                    Section {
                        Picker("Remind every", selection: $checkInInterval) {
                            Text("2 days").tag(2)
                            Text("3 days").tag(3)
                            Text("5 days").tag(5)
                            Text("1 week").tag(7)
                            Text("2 weeks").tag(14)
                            Text("1 month").tag(30)
                        }
                        Button {
                            // Reset to the timeline-derived smart default.
                            let provisional = Goal(
                                title: title,
                                targetDate: hasTargetDate ? DateFormatting.dateString(targetDate) : nil,
                                goalType: goalType
                            )
                            checkInInterval = GoalEngine.defaultCheckInIntervalDays(for: provisional)
                        } label: {
                            Label("Use smart default for this timeline",
                                  systemImage: "sparkles")
                                .font(.caption)
                        }
                        Button {
                            // Clear the per-goal override: snap back to the
                            // global check-in cadence set in Settings →
                            // Reflection Cadence.
                            checkInInterval = NotificationService.defaultCheckInInterval
                        } label: {
                            Label("Follow my global cadence",
                                  systemImage: "globe")
                                .font(.caption)
                        }
                    } header: {
                        Text("Check-in Frequency")
                    } footer: {
                        Text("Shorter goals deserve shorter cadence. A 7-day goal should probably be checked in every 2 days, not every 2 weeks.")
                            .font(.caption2)
                    }
                }

                if isLifelong {
                    supportingGoalsSection
                } else {
                    Section("Milestones") {
                        ForEach($milestoneTexts) { $row in
                            HStack {
                                if goal != nil {
                                    Button {
                                        row.completed.toggle()
                                    } label: {
                                        Image(systemName: row.completed ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(row.completed ? .success : .textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                TextField("Milestone", text: $row.text)
                            }
                        }
                        .onDelete { indices in
                            milestoneTexts.remove(atOffsets: indices)
                        }
                        Button {
                            milestoneTexts.append(MilestoneRow(id: UUID(), text: "", completed: false))
                        } label: {
                            Label("Add milestone", systemImage: "plus")
                        }
                    }
                }

                #if os(iOS)
                if !isLifelong {
                    Section("Schedule on Calendar") {
                        Button {
                            showCalendarScheduler = true
                        } label: {
                            Label("Add Work Block to Calendar", systemImage: "calendar.badge.plus")
                        }
                        if let msg = scheduleMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.success)
                        }
                        Text("Schedule time on your Apple Calendar to work on this goal. MortalLoom can create one-time or recurring blocks.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                #endif

                if isEditingExisting {
                    signalMutingSection
                }

                if isEditingExisting, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Goal", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .macGroupedFormStyle()
            .navigationTitle(prefillEvidence != nil ? "Suggested Goal" : (goal == nil ? "New Goal" : "Edit Goal"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Goal", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this goal?")
            }
            #if os(iOS)
            .sheet(isPresented: $showCalendarScheduler) {
                CalendarSchedulerSheet(
                    goalId: goal?.id,
                    goalTitle: title,
                    goalNotes: notes,
                    goalTargetDate: hasTargetDate ? targetDate : nil
                ) { msg in
                    scheduleMessage = msg
                }
            }
            #endif
            .sheet(isPresented: $showingAddChild) {
                if let parent = goal, let addChild = onAddChild {
                    // Apex → adds sub-apex (Life Pillar); sub-apex → adds standard goal.
                    let childType: GoalType = (parent.goalType == .apex) ? .subApex : .standard
                    GoalEditSheet(
                        goal: nil,
                        allGoals: allGoals,
                        allHabits: allHabits,
                        defaultGoalType: childType,
                        defaultParentId: parent.id,
                        onSave: { newChild in addChild(newChild) },
                        onAddChild: onAddChild
                    )
                }
            }
        }
        .macSheetFrame()
    }

    /// Show the list of stagnation signal titles currently firing for this
    /// goal, with a toggle to mute each one. Muted signals are filtered out
    /// of StagnationEngine output for this specific goal. Global signals
    /// (apex-wide) can't be muted here because they apply across goals.
    @ViewBuilder
    private var signalMutingSection: some View {
        let firing = currentSignalsForGoal
        let mutedNotFiring = mutedSignals.filter { title in !firing.contains { $0.title == title } }

        if !firing.isEmpty || !mutedNotFiring.isEmpty {
            Section {
                ForEach(firing) { signal in
                    Toggle(isOn: Binding(
                        get: { !mutedSignals.contains(signal.title) },
                        set: { on in
                            if on { mutedSignals.remove(signal.title) }
                            else { mutedSignals.insert(signal.title) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(signal.title)
                                .font(.caption).fontWeight(.semibold)
                            Text(signal.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                ForEach(Array(mutedNotFiring), id: \.self) { title in
                    Toggle(isOn: Binding(
                        get: { !mutedSignals.contains(title) },
                        set: { on in
                            if on { mutedSignals.remove(title) }
                            else { mutedSignals.insert(title) }
                        }
                    )) {
                        Text("\(title) (muted)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Stagnation Alerts")
            } footer: {
                Text("Toggle off to mute a specific alert for this goal. You can re-enable it any time.")
                    .font(.caption2)
            }
        }
    }

    /// Stagnation signals currently applicable to the goal being edited.
    /// Used to present the muting toggles. Computed against the current
    /// state of the goal list, not the edited fields, so live edits don't
    /// flip alerts mid-form.
    ///
    /// Habits are passed so the goal-level signals reflect habit activity —
    /// a linked daily habit completed recently keeps the goal "fresh" and
    /// stops a slipping/check-in signal from firing here.
    ///
    /// Only **goal-level** signals (`habitId == nil`) are surfaced for
    /// muting. Muting is persisted by signal *title* (`Goal.mutedSignals`),
    /// and every per-habit "Habit is slipping" signal shares that one title —
    /// so exposing them here would let muting one habit's alert silence every
    /// habit alert on the goal. Per-habit muting needs habit-identity-keyed
    /// persistence, which is out of scope for this view.
    private var currentSignalsForGoal: [StagnationSignal] {
        guard let goalId = goal?.id else { return [] }
        let all = StagnationEngine.signals(goals: allGoals, habits: allHabits)
        return all.filter { $0.goalId == goalId && $0.habitId == nil }
    }

    @ViewBuilder
    private var supportingGoalsSection: some View {
        Section {
            if goal == nil {
                Text("Save this \(goalType?.label ?? "goal") first, then add supporting goals that feed into it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if supportingGoals.isEmpty {
                Text("No supporting goals yet. Add concrete goals that feed into this \(goalType?.label.lowercased() ?? "goal").")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(supportingGoals, id: \.id) { g in
                    HStack {
                        if let iconName = g.goalType?.icon {
                            Image(systemName: iconName)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        Text(g.title)
                            .foregroundColor(.primary)
                        Spacer()
                        if g.goalType != .apex && g.goalType != .subApex {
                            Text("\(Int(g.progressPercent))%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            if goal != nil && onAddChild != nil {
                Button {
                    showingAddChild = true
                } label: {
                    Label("Add supporting goal", systemImage: "plus")
                }
            }
        } header: {
            Text("Supporting Goals")
        } footer: {
            Text("Lifetime purposes don't have a progress bar — they're measured by the alignment of supporting goals feeding into them.")
                .font(.caption2)
        }
    }

    /// Goals that can be selected as parent — excludes self and own descendants to prevent cycles.
    private var parentCandidates: [Goal] {
        guard let currentId = goal?.id else { return allGoals }
        var excludeIds: Set<UUID> = [currentId]
        // Walk descendants to prevent circular references
        var queue = [currentId]
        while !queue.isEmpty {
            let id = queue.removeFirst()
            for g in allGoals where g.parentId == id && !excludeIds.contains(g.id) {
                excludeIds.insert(g.id)
                queue.append(g.id)
            }
        }
        return allGoals.filter { !excludeIds.contains($0.id) }
    }

    private func save() {
        let milestones = milestoneTexts
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { row in
                if let existing = goal?.milestones.first(where: { $0.id == row.id }) {
                    return GoalMilestone(
                        id: existing.id,
                        title: row.text,
                        completed: row.completed,
                        completedDate: row.completed && !existing.completed ? DateFormatting.todayString() : existing.completedDate
                    )
                }
                return GoalMilestone(id: row.id, title: row.text, completed: row.completed,
                                     completedDate: row.completed ? DateFormatting.todayString() : nil)
            }

        // For the prefilled-suggested flow, always create a fresh Goal (don't
        // reuse the prefill goal's id) so saving doesn't accidentally
        // overwrite a real existing goal. Mirrors HabitEditSheet.save().
        var result: Goal
        if isEditingExisting, let g = goal {
            result = g
        } else {
            result = Goal(title: title)
            if let evidence = prefillEvidence {
                result.geneticEvidence = evidence
            }
        }
        result.title = title.trimmingCharacters(in: .whitespaces)
        result.notes = notes.trimmingCharacters(in: .whitespaces)
        result.priority = priority
        result.parentId = parentId
        result.category = category
        result.goalType = goalType
        result.mutedSignals = Array(mutedSignals).sorted()

        if isLifelong {
            // Lifetime purposes: no end date, no text milestones, no progress check-ins.
            // Their structure comes from supporting child goals in the tree.
            result.targetDate = nil
            result.milestones = []
            result.horizon = goalType == .apex ? .lifetime : (horizon ?? .lifetime)
            result.checkInIntervalDays = checkInInterval // retained for future reflection cadence
        } else {
            result.targetDate = hasTargetDate ? DateFormatting.dateString(targetDate) : nil
            result.checkInIntervalDays = checkInInterval
            result.milestones = milestones
            result.horizon = horizon

            if !milestones.isEmpty, let lastCheckIn = result.checkIns.last {
                let milestonePct = Double(milestones.filter(\.completed).count) / Double(milestones.count) * 100
                if milestonePct != lastCheckIn.progressPct {
                    result.checkIns.append(GoalCheckIn(progressPct: milestonePct, note: "Updated milestones"))
                }
            }
        }

        onSave(result)
        dismiss()
    }
}
