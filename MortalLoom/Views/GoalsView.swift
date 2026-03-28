import SwiftUI

// MARK: - GoalsView

struct GoalsView: View {
    @State private var goals: [Goal] = []
    @State private var deathClock: DeathClockEngine.DeathClockResult?
    @State private var projections: [UUID: GoalEngine.GoalProjection] = [:]
    @State private var cognitiveDeadline: Date?
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var checkInGoal: Goal?

    // Partitioned goal lists — computed once per data load
    @State private var attentionGoals: [Goal] = []
    @State private var onTrackGoals: [Goal] = []
    @State private var pausedGoals: [Goal] = []
    @State private var doneGoals: [Goal] = []
    @State private var activeCount = 0
    @State private var completedCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                needsAttentionSection
                activeGoalsSection
                completedGoalsSection
            }
            .padding()
        }
        .background(Color.bg)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddGoal = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            GoalEditSheet(goal: nil, allGoals: goals) { newGoal in
                saveAndReload { await DataStore.shared.addGoal(newGoal) }
            }
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditSheet(goal: goal, allGoals: goals) { updated in
                saveAndReload { await DataStore.shared.updateGoal(updated) }
            }
        }
        .sheet(item: $checkInGoal) { goal in
            CheckInSheet(goal: goal) { updated in
                saveAndReload { await DataStore.shared.updateGoal(updated) }
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
            Task { await loadData() }
        }
    }

    private func saveAndReload(_ action: @escaping () async -> Void) {
        Task {
            await action()
            await loadData()
        }
    }

    private func loadData() async {
        let data = await DataStore.shared.getData()
        let dc = DeathClockEngine.calculate(
            birthDateStr: data.profile.birthDate ?? "",
            sex: data.profile.biologicalSex,
            lifestyle: data.profile.lifestyle,
            genome: data.genomeScanRecord
        )
        let cogDate = GoalEngine.cognitiveDeadline(from: dc)

        // Compute all projections once
        var projs: [UUID: GoalEngine.GoalProjection] = [:]
        for goal in data.goals {
            projs[goal.id] = GoalEngine.project(
                goal: goal, deathDate: dc?.deathDate, healthyCognitiveDate: cogDate
            )
        }

        // Partition goals into sections
        var attention: [Goal] = []
        var onTrack: [Goal] = []
        var paused: [Goal] = []
        var done: [Goal] = []
        var activeN = 0
        var completedN = 0

        for goal in data.goals {
            switch goal.status {
            case .active:
                activeN += 1
                if goal.needsCheckIn || goal.isOverdue {
                    attention.append(goal)
                } else {
                    onTrack.append(goal)
                }
            case .paused:
                paused.append(goal)
            case .completed:
                completedN += 1
                done.append(goal)
            case .abandoned:
                done.append(goal)
            }
        }

        onTrack.sort { $0.priority < $1.priority }
        done.sort { $0.completedDate ?? $0.createdDate > $1.completedDate ?? $1.createdDate }

        goals = data.goals
        deathClock = dc
        cognitiveDeadline = cogDate
        projections = projs
        attentionGoals = attention
        onTrackGoals = onTrack
        pausedGoals = paused
        doneGoals = done
        activeCount = activeN
        completedCount = completedN
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Life Goals")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    if let dc = deathClock {
                        Text("\(String(format: "%.1f", dc.healthyYearsRemaining)) healthy years remaining")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(activeCount) active")
                        .font(.caption).foregroundColor(.textSecondary)
                    Text("\(completedCount) completed")
                        .font(.caption).foregroundColor(.success)
                    if !attentionGoals.isEmpty {
                        Text("\(attentionGoals.count) need attention")
                            .font(.caption).fontWeight(.medium)
                            .foregroundColor(.warning)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Sections

    @ViewBuilder
    private var needsAttentionSection: some View {
        if !attentionGoals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "NEEDS ATTENTION")
                goalTreeSection(attentionGoals)
            }
        }
    }

    @ViewBuilder
    private var activeGoalsSection: some View {
        if !onTrackGoals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "ON TRACK")
                goalTreeSection(onTrackGoals)
            }
        }

        if !pausedGoals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "PAUSED")
                goalTreeSection(pausedGoals)
            }
        }

        if attentionGoals.isEmpty && onTrackGoals.isEmpty && pausedGoals.isEmpty {
            EmptyStateView(
                icon: "target",
                title: "No goals yet",
                subtitle: "Map your ambitions to the time you have left"
            )
        }
    }

    @ViewBuilder
    private var completedGoalsSection: some View {
        if !doneGoals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "COMPLETED")
                goalTreeSection(doneGoals)
            }
        }
    }

    /// Render a section's goals as a tree: top-level goals with children nested underneath.
    @ViewBuilder
    private func goalTreeSection(_ sectionGoals: [Goal]) -> some View {
        let sectionIds = Set(sectionGoals.map(\.id))
        let topLevel = sectionGoals.filter { g in g.parentId.map { sectionIds.contains($0) } != true }
        let childrenByParent = Dictionary(grouping: sectionGoals.filter { g in
            g.parentId.map { sectionIds.contains($0) } == true
        }, by: { $0.parentId ?? UUID() })

        ForEach(topLevel) { parent in
            goalCard(parent)
            if let children = childrenByParent[parent.id] {
                ForEach(children) { child in
                    goalCard(child)
                        .padding(.leading, 24)
                }
            }
        }
    }

    // MARK: - Goal Card

    private func goalCard(_ goal: Goal) -> some View {
        let projection = projections[goal.id] ?? GoalEngine.project(
            goal: goal, deathDate: deathClock?.deathDate, healthyCognitiveDate: cognitiveDeadline
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                priorityDot(goal.priority)
                goalTypeBadge(goal.goalType)
                Text(goal.title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
                urgencyBadge(projection.urgencyLevel, status: goal.status)
            }

            if goal.category != nil || goal.horizon != nil {
                HStack(spacing: 6) {
                    if let cat = goal.category {
                        categoryChip(cat)
                    }
                    if let hz = goal.horizon {
                        horizonChip(hz)
                    }
                }
            }

            if goal.status == .active || goal.status == .paused {
                progressBar(goal.progressPercent)
            }

            HStack(spacing: 16) {
                if goal.status == .active || goal.status == .paused {
                    if let days = projection.daysToCompletion {
                        infoChip(icon: "clock", text: DateFormatting.formatDuration(days))
                    }

                    if projection.slippageDays > 0 {
                        infoChip(icon: "exclamationmark.triangle", text: "+\(DateFormatting.formatDuration(projection.slippageDays))", color: .warning)
                    }

                    if goal.needsCheckIn {
                        infoChip(icon: "bell.badge", text: "Check in", color: .warning)
                    }

                    if let target = goal.targetDate {
                        infoChip(icon: "calendar", text: DateFormatting.displayDate(target))
                    }

                    if !goal.milestones.isEmpty {
                        let done = goal.milestones.filter(\.completed).count
                        infoChip(icon: "checkmark.circle", text: "\(done)/\(goal.milestones.count)")
                    }
                }

                if goal.status == .completed, let date = goal.completedDate {
                    infoChip(icon: "checkmark.circle.fill", text: DateFormatting.displayDate(date), color: .success)
                }

                if goal.status == .abandoned {
                    infoChip(icon: "xmark.circle", text: "Abandoned", color: .textMuted)
                }

                Spacer()
            }

            if projection.exceedsLifespan {
                lifespanWarning("At your current pace, this goal extends beyond your expected lifespan. Prioritize it now or accept it may not happen.")
            } else if projection.exceedsCognitiveYears {
                lifespanWarning("This goal's timeline extends past your estimated healthy cognitive years. Consider accelerating progress or breaking it into smaller achievable goals.")
            }
        }
        .padding()
        .cardStyle()
        .contextMenu {
            if goal.status == .active {
                Button { checkInGoal = goal } label: {
                    Label("Check In", systemImage: "pencil.and.list.clipboard")
                }
            }
            Button { editingGoal = goal } label: {
                Label("Edit", systemImage: "pencil")
            }
            if goal.status == .active {
                Button { updateGoalStatus(goal, to: .paused) } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                Button { completeGoal(goal) } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle")
                }
            }
            if goal.status == .paused {
                Button { updateGoalStatus(goal, to: .active) } label: {
                    Label("Resume", systemImage: "play.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                saveAndReload { await DataStore.shared.removeGoal(id: goal.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onTapGesture {
            if goal.status == .active {
                checkInGoal = goal
            } else {
                editingGoal = goal
            }
        }
    }

    // MARK: - Status Mutations

    private func updateGoalStatus(_ goal: Goal, to status: GoalStatus) {
        saveAndReload {
            var g = goal
            g.status = status
            await DataStore.shared.updateGoal(g)
        }
    }

    private func completeGoal(_ goal: Goal) {
        saveAndReload {
            var g = goal
            g.status = .completed
            g.completedDate = DateFormatting.todayString()
            g.checkIns.append(GoalCheckIn(progressPct: 100, note: "Goal completed"))
            await DataStore.shared.updateGoal(g)
        }
    }

    // MARK: - UI Components

    private func progressBar(_ pct: Double) -> some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.bgInput)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(pct >= 75 ? Color.success : pct >= 40 ? Color.accentColor : Color.warning)
                        .frame(width: geo.size.width * (pct / 100))
                }
            }
            .frame(height: 8)
            Text("\(Int(pct))%")
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func priorityDot(_ priority: GoalPriority) -> some View {
        Circle()
            .fill(priorityColor(priority))
            .frame(width: 8, height: 8)
    }

    private func priorityColor(_ priority: GoalPriority) -> Color {
        switch priority {
        case .high: .danger
        case .medium: .warning
        case .low: .textMuted
        }
    }

    private func urgencyBadge(_ urgency: GoalEngine.UrgencyLevel, status: GoalStatus) -> some View {
        let (text, color): (String, Color) = {
            if status == .completed { return ("Done", .success) }
            if status == .paused { return ("Paused", .textMuted) }
            if status == .abandoned { return ("Abandoned", .textMuted) }
            switch urgency {
            case .onTrack: return ("On Track", .success)
            case .slipping: return ("Slipping", .warning)
            case .atRisk: return ("At Risk", .warning)
            case .critical: return ("Critical", .danger)
            case .impossible: return ("Beyond Lifespan", .danger)
            }
        }()

        return Text(text)
            .font(.caption2).fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }

    private func infoChip(icon: String, text: String, color: Color = .textSecondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(color)
    }

    @ViewBuilder
    private func goalTypeBadge(_ goalType: GoalType?) -> some View {
        if let gt = goalType, gt != .standard {
            Image(systemName: gt.icon)
                .font(.caption2)
                .foregroundColor(gt == .apex ? .warning : .accentColor)
        }
    }

    private func categoryChip(_ cat: GoalCategory) -> some View {
        HStack(spacing: 3) {
            Image(systemName: cat.icon)
                .font(.system(size: 9))
            Text(cat.label)
                .font(.system(size: 10))
        }
        .foregroundColor(cat.swiftUIColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(cat.swiftUIColor.opacity(0.15))
        .cornerRadius(4)
    }

    private func horizonChip(_ hz: GoalHorizon) -> some View {
        Text(hz.label)
            .font(.system(size: 10))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.textSecondary.opacity(0.12))
            .cornerRadius(4)
    }


    private func lifespanWarning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.danger)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundColor(.danger)
        }
        .padding(10)
        .background(Color.danger.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Goal Edit Sheet

private struct GoalEditSheet: View {
    let goal: Goal?
    let allGoals: [Goal]
    let onSave: (Goal) -> Void
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

    private struct MilestoneRow: Identifiable {
        let id: UUID
        var text: String
        var completed: Bool
    }

    init(goal: Goal?, allGoals: [Goal] = [], onSave: @escaping (Goal) -> Void) {
        self.goal = goal
        self.allGoals = allGoals
        self.onSave = onSave
        let g = goal
        _title = State(initialValue: g?.title ?? "")
        _notes = State(initialValue: g?.notes ?? "")
        _hasTargetDate = State(initialValue: g?.targetDate != nil)
        _targetDate = State(initialValue: {
            if let t = g?.targetDate { return DateFormatting.dateFromString(t) ?? Date() }
            return Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        }())
        _priority = State(initialValue: g?.priority ?? .medium)
        _checkInInterval = State(initialValue: g?.checkInIntervalDays ?? 7)
        _milestoneTexts = State(initialValue: g?.milestones.map {
            MilestoneRow(id: $0.id, text: $0.title, completed: $0.completed)
        } ?? [])
        _parentId = State(initialValue: g?.parentId)
        _horizon = State(initialValue: g?.horizon)
        _category = State(initialValue: g?.category)
        _goalType = State(initialValue: g?.goalType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("What do you want to achieve?", text: $title)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Classification") {
                    Picker("Type", selection: $goalType) {
                        Text("None").tag(GoalType?.none)
                        ForEach(GoalType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.icon).tag(GoalType?.some(t))
                        }
                    }

                    Picker("Category", selection: $category) {
                        Text("None").tag(GoalCategory?.none)
                        ForEach(GoalCategory.allCases, id: \.self) { c in
                            Label(c.label, systemImage: c.icon).tag(GoalCategory?.some(c))
                        }
                    }

                    Picker("Horizon", selection: $horizon) {
                        Text("None").tag(GoalHorizon?.none)
                        ForEach(GoalHorizon.allCases, id: \.self) { h in
                            Text(h.label).tag(GoalHorizon?.some(h))
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

                Section("Deadline") {
                    Toggle("Set target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Target", selection: $targetDate, displayedComponents: .date)
                    }
                }

                Section("Check-in Frequency") {
                    Picker("Remind every", selection: $checkInInterval) {
                        Text("3 days").tag(3)
                        Text("1 week").tag(7)
                        Text("2 weeks").tag(14)
                        Text("1 month").tag(30)
                    }
                }

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
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
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

        var result = goal ?? Goal(title: title)
        result.title = title.trimmingCharacters(in: .whitespaces)
        result.notes = notes.trimmingCharacters(in: .whitespaces)
        result.targetDate = hasTargetDate ? DateFormatting.dateString(targetDate) : nil
        result.priority = priority
        result.checkInIntervalDays = checkInInterval
        result.milestones = milestones
        result.parentId = parentId
        result.horizon = horizon
        result.category = category
        result.goalType = goalType

        if !milestones.isEmpty, let lastCheckIn = result.checkIns.last {
            let milestonePct = Double(milestones.filter(\.completed).count) / Double(milestones.count) * 100
            if milestonePct != lastCheckIn.progressPct {
                result.checkIns.append(GoalCheckIn(progressPct: milestonePct, note: "Updated milestones"))
            }
        }

        onSave(result)
        dismiss()
    }
}

// MARK: - Check-In Sheet

private struct CheckInSheet: View {
    let goal: Goal
    let onSave: (Goal) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var progressPct: Double
    @State private var note: String = ""
    @State private var milestoneStates: [UUID: Bool]

    init(goal: Goal, onSave: @escaping (Goal) -> Void) {
        self.goal = goal
        self.onSave = onSave
        _progressPct = State(initialValue: goal.progressPercent)
        _milestoneStates = State(initialValue: Dictionary(uniqueKeysWithValues: goal.milestones.map { ($0.id, $0.completed) }))
    }

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Check In: \(goal.title)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func updateProgressFromMilestones() {
        let total = goal.milestones.count
        guard total > 0 else { return }
        let done = milestoneStates.values.filter { $0 }.count
        progressPct = Double(done) / Double(total) * 100
    }

    private func save() {
        var updated = goal

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

        onSave(updated)
        dismiss()
    }
}
