import SwiftUI

// MARK: - GoalsView

struct GoalsView: View {
    @State private var goals: [Goal] = []
    @State private var deathClock: DeathClockEngine.DeathClockResult?
    @State private var levDeathClock: DeathClockEngine.DeathClockResult?
    @State private var projections: [UUID: GoalEngine.GoalProjection] = [:]
    @State private var cognitiveDeadline: Date?
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var checkInGoal: Goal?

    @State private var apexGoal: Goal?
    @State private var hierarchyItems: [HierarchyItem] = []
    @State private var childCounts: [UUID: Int] = [:]
    @State private var doneGoals: [Goal] = []
    @State private var activeCount = 0
    @State private var completedCount = 0
    @State private var attentionCount = 0

    // Cached for reflatten without full reload
    @State private var cachedRoots: [Goal] = []
    @State private var cachedActiveByParent: [UUID?: [Goal]] = [:]

    private static let treeLineColor = Color.textMuted.opacity(0.4)
    private static let treeLineWidth: CGFloat = 1.5
    private static let treeColumnWidth: CGFloat = 24

    private struct HierarchyItem: Identifiable {
        let goal: Goal
        let depth: Int
        let isLastChild: Bool
        let continuingDepths: Set<Int>
        let hasChildren: Bool
        var id: UUID { goal.id }
    }

    @State private var collapsedIds: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                apexSection
                hierarchySection
                completedGoalsSection
            }
            .padding()
        }
        .background(Color.bg)
        #if os(macOS)
        // macOS still has a NavigationSplitView host that renders toolbar items.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddGoal = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        #endif
        .sheet(isPresented: $showingAddGoal) {
            GoalEditSheet(goal: nil, allGoals: goals) { newGoal in
                saveAndReload { await DataStore.shared.addGoal(newGoal) }
            }
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditSheet(goal: goal, allGoals: goals, onSave: { updated in
                saveAndReload { await DataStore.shared.updateGoal(updated) }
            }, onDelete: {
                saveAndReload { await DataStore.shared.removeGoal(id: goal.id) }
            })
        }
        .sheet(item: $checkInGoal) { goal in
            CheckInSheet(goal: goal) { updated in
                saveAndReload { await DataStore.shared.updateGoal(updated) }
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
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
            genome: data.genomeScanRecord,
            locationProfile: data.profile.locationProfile,
            healthMetrics: data.healthMetrics
        )
        let levDc: DeathClockEngine.DeathClockResult? = dc.flatMap {
            DeathClockEngine.calculateLEVResult(
                standardResult: $0,
                birthDateStr: data.profile.birthDate ?? "",
                levTargetAge: data.profile.levTargetAge
            )
        }
        let cogDate = GoalEngine.cognitiveDeadline(from: dc)

        var projs: [UUID: GoalEngine.GoalProjection] = [:]
        for goal in data.goals {
            projs[goal.id] = GoalEngine.project(
                goal: goal, deathDate: dc?.deathDate, healthyCognitiveDate: cogDate
            )
        }

        let activeGoals = data.goals.filter { $0.status == .active || $0.status == .paused }
        let done = data.goals.filter { $0.status == .completed || $0.status == .abandoned }
            .sorted { $0.completedDate ?? $0.createdDate > $1.completedDate ?? $1.createdDate }

        let apex = activeGoals.first { $0.goalType == .apex }
        let activeIds = Set(activeGoals.map(\.id))
        let activeByParent = Dictionary(grouping: activeGoals, by: \.parentId)

        // Precompute active child counts for all goals
        var counts: [UUID: Int] = [:]
        for goal in data.goals {
            counts[goal.id] = (activeByParent[goal.id] ?? []).count
        }

        var roots = activeGoals.filter { g in
            g.id != apex?.id &&
            (g.parentId == nil || !activeIds.contains(g.parentId!))
        }

        if let apex {
            let apexChildren = (activeByParent[apex.id] ?? [])
                .sorted { goalTypeOrder($0) < goalTypeOrder($1) }
            let otherRoots = roots.filter { $0.parentId != apex.id }
                .sorted { $0.priority < $1.priority }
            roots = apexChildren + otherRoots
        } else {
            roots.sort { goalTypeOrder($0) < goalTypeOrder($1) }
        }

        goals = data.goals
        deathClock = dc
        levDeathClock = levDc
        cognitiveDeadline = cogDate
        projections = projs
        apexGoal = apex
        childCounts = counts
        doneGoals = done
        activeCount = activeGoals.count
        completedCount = done.count { $0.status == .completed }
        attentionCount = activeGoals.count { $0.needsCheckIn || $0.isOverdue }
        cachedRoots = roots
        cachedActiveByParent = activeByParent
        hierarchyItems = buildHierarchy(roots: roots, activeByParent: activeByParent)
    }

    private func buildHierarchy(roots: [Goal], activeByParent: [UUID?: [Goal]]) -> [HierarchyItem] {
        var items: [HierarchyItem] = []
        var visited = Set<UUID>()
        func flatten(_ goal: Goal, depth: Int, isLast: Bool, continuing: Set<Int>) {
            guard visited.insert(goal.id).inserted else { return }
            let children = (activeByParent[goal.id] ?? [])
                .sorted { $0.priority < $1.priority }
            items.append(HierarchyItem(
                goal: goal, depth: depth, isLastChild: isLast,
                continuingDepths: continuing, hasChildren: !children.isEmpty
            ))
            guard !collapsedIds.contains(goal.id) else { return }
            for (i, child) in children.enumerated() {
                let childIsLast = i == children.count - 1
                var childContinuing = continuing
                if childIsLast {
                    childContinuing.remove(depth + 1)
                } else {
                    childContinuing.insert(depth + 1)
                }
                flatten(child, depth: depth + 1, isLast: childIsLast, continuing: childContinuing)
            }
        }
        for (i, root) in roots.enumerated() {
            flatten(root, depth: 0, isLast: i == roots.count - 1, continuing: i < roots.count - 1 ? [0] : [])
        }
        return items
    }

    private func goalTypeOrder(_ goal: Goal) -> Int {
        switch goal.goalType {
        case .apex: 0
        case .subApex: 1
        case .standard: 2
        case nil: 3
        }
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
                        let years = String(format: "%.1f", dc.healthyYearsRemaining)
                        let label = if let lev = levDeathClock {
                            "\(years) – \(String(format: "%.1f", lev.healthyYearsRemaining)) healthy years remaining"
                        } else {
                            "\(years) healthy years remaining"
                        }
                        Text(label)
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
                    if attentionCount > 0 {
                        Text("\(attentionCount) need attention")
                            .font(.caption).fontWeight(.medium)
                            .foregroundColor(.warning)
                    }
                }
                #if os(iOS)
                // No NavigationStack on iOS root, so toolbar(.primaryAction)
                // wouldn't render — surface the add button inline instead.
                Button { showingAddGoal = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add goal")
                .padding(.leading, 8)
                #endif
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Apex Section

    @ViewBuilder
    private var apexSection: some View {
        if let apex = apexGoal {
            apexCard(apex)
        }
    }

    private func apexCard(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundColor(.warning)
                Text("North Star")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.warning)
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
            }

            Text(goal.title)
                .font(.title3).fontWeight(.bold)
                .foregroundColor(.textPrimary)

            if !goal.notes.isEmpty {
                Text(goal.notes)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .lineLimit(3)
            }

            classificationChips(for: goal)

            let count = childCounts[goal.id] ?? 0
            if count > 0 {
                Text("\(count) supporting goal\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
        }
        .padding()
        .cardStyle(fill: .warning.opacity(0.08), border: .warning.opacity(0.3), radius: 16)
        .contextMenu { goalContextMenu(for: goal, isLifelong: true) }
        .onTapGesture { editingGoal = goal }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("North Star goal: \(goal.title)")
        .accessibilityHint("Tap to edit")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Hierarchy Section

    @ViewBuilder
    private var hierarchySection: some View {
        if !hierarchyItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(hierarchyItems) { item in
                    treeRow(item: item)
                }
            }
        }

        if hierarchyItems.isEmpty && apexGoal == nil {
            EmptyStateView(
                icon: "target",
                title: "No goals yet",
                subtitle: "Map your ambitions to the time you have left"
            )
        }
    }

    private func treeRow(item: HierarchyItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if item.depth > 0 {
                treeConnectors(item: item)
            }
            goalCard(item.goal)
                .overlay(alignment: .topLeading) {
                    if item.hasChildren {
                        collapseToggle(for: item.goal.id)
                            .offset(x: -6, y: -6)
                    }
                }
        }
    }

    private func treeConnectors(item: HierarchyItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<item.depth, id: \.self) { level in
                if level == item.depth - 1 {
                    branchConnector(isLast: item.isLastChild)
                } else {
                    verticalLine(continues: item.continuingDepths.contains(level))
                }
            }
        }
    }

    private func branchConnector(isLast: Bool) -> some View {
        Canvas { context, size in
            let midX = size.width / 2
            let midY = Self.treeColumnWidth

            var path = Path()
            path.move(to: CGPoint(x: midX, y: 0))
            path.addLine(to: CGPoint(x: midX, y: midY))
            path.addLine(to: CGPoint(x: size.width, y: midY))

            if !isLast {
                path.move(to: CGPoint(x: midX, y: midY))
                path.addLine(to: CGPoint(x: midX, y: size.height))
            }

            context.stroke(path, with: .color(Self.treeLineColor), lineWidth: Self.treeLineWidth)
        }
        .frame(width: Self.treeColumnWidth)
    }

    private func verticalLine(continues: Bool) -> some View {
        Canvas { context, size in
            guard continues else { return }
            let midX = size.width / 2
            var path = Path()
            path.move(to: CGPoint(x: midX, y: 0))
            path.addLine(to: CGPoint(x: midX, y: size.height))
            context.stroke(path, with: .color(Self.treeLineColor), lineWidth: Self.treeLineWidth)
        }
        .frame(width: Self.treeColumnWidth)
    }

    private func collapseToggle(for id: UUID) -> some View {
        let isCollapsed = collapsedIds.contains(id)
        let count = childCounts[id] ?? 0
        return Button {
            if isCollapsed {
                collapsedIds.remove(id)
            } else {
                collapsedIds.insert(id)
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                hierarchyItems = buildHierarchy(roots: cachedRoots, activeByParent: cachedActiveByParent)
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: isCollapsed ? "chevron.right.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.textMuted)
                if isCollapsed && count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.textMuted)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.bgCard)
                    .padding(-2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand \(count) children" : "Collapse children")
    }

    // MARK: - Completed

    @ViewBuilder
    private var completedGoalsSection: some View {
        if !doneGoals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "COMPLETED")
                ForEach(doneGoals) { goal in
                    goalCard(goal)
                }
            }
        }
    }

    // MARK: - Goal Card

    private func goalCard(_ goal: Goal) -> some View {
        let isLifelong = goal.goalType == .subApex
        let projection = projections[goal.id] ?? GoalEngine.project(
            goal: goal, deathDate: deathClock?.deathDate, healthyCognitiveDate: cognitiveDeadline
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                if !isLifelong {
                    priorityDot(goal.priority)
                }
                goalTypeBadge(goal.goalType)
                Text(goal.title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
                if goal.needsCheckIn || goal.isOverdue {
                    Image(systemName: "bell.badge.fill")
                        .font(.caption)
                        .foregroundColor(.warning)
                }
                if !isLifelong {
                    urgencyBadge(projection.urgencyLevel, status: goal.status)
                }
            }

            if isLifelong && !goal.notes.isEmpty {
                Text(goal.notes)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }

            classificationChips(for: goal)

            if !isLifelong && (goal.status == .active || goal.status == .paused) {
                progressBar(goal.progressPercent)
            }

            if isLifelong {
                let count = childCounts[goal.id] ?? 0
                if count > 0 {
                    Text("\(count) sub-goal\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
            }

            HStack(spacing: 16) {
                if !isLifelong && (goal.status == .active || goal.status == .paused) {
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
                        let doneCount = goal.milestones.filter(\.completed).count
                        infoChip(icon: "checkmark.circle", text: "\(doneCount)/\(goal.milestones.count)")
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

            if !isLifelong && projection.exceedsLifespan {
                lifespanWarning("At your current pace, this goal extends beyond your expected lifespan. Prioritize it now or accept it may not happen.")
            } else if !isLifelong && projection.exceedsCognitiveYears {
                lifespanWarning("This goal's timeline extends past your estimated healthy cognitive years. Consider accelerating progress or breaking it into smaller achievable goals.")
            }
        }
        .padding()
        .cardStyle(
            fill: isLifelong ? .accentColor.opacity(0.06) : .bgCard,
            border: isLifelong ? .accentColor.opacity(0.2) : .cardBorder
        )
        .contextMenu { goalContextMenu(for: goal, isLifelong: isLifelong) }
        .onTapGesture {
            if isLifelong {
                editingGoal = goal
            } else if goal.status == .active {
                checkInGoal = goal
            } else {
                editingGoal = goal
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isLifelong ? "Life pillar: " : "")\(goal.title), \(goal.status.rawValue)\(isLifelong ? "" : ", \(Int(goal.progressPercent))% complete")")
        .accessibilityHint(isLifelong ? "Tap to edit" : (goal.status == .active ? "Tap to check in" : "Tap to edit"))
        .accessibilityAddTraits(.isButton)
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

    // MARK: - Shared Helpers

    @ViewBuilder
    private func classificationChips(for goal: Goal) -> some View {
        if goal.category != nil || goal.horizon != nil {
            HStack(spacing: 6) {
                if let cat = goal.category { categoryChip(cat) }
                if let hz = goal.horizon { horizonChip(hz) }
            }
        }
    }

    @ViewBuilder
    private func goalContextMenu(for goal: Goal, isLifelong: Bool) -> some View {
        if goal.status == .active && !isLifelong {
            Button { checkInGoal = goal } label: {
                Label("Check In", systemImage: "pencil.and.list.clipboard")
            }
        }
        Button { editingGoal = goal } label: {
            Label("Edit", systemImage: "pencil")
        }
        if goal.status == .active && !isLifelong {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress: \(Int(pct)) percent")
        .accessibilityValue("\(Int(pct)) percent")
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

struct GoalEditSheet: View {
    let goal: Goal?
    let allGoals: [Goal]
    let onSave: (Goal) -> Void
    let onDelete: (() -> Void)?
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
    @State private var showCalendarScheduler = false
    @State private var scheduleMessage: String?

    private struct MilestoneRow: Identifiable {
        let id: UUID
        var text: String
        var completed: Bool
    }

    init(goal: Goal?, allGoals: [Goal] = [], onSave: @escaping (Goal) -> Void, onDelete: (() -> Void)? = nil) {
        self.goal = goal
        self.allGoals = allGoals
        self.onSave = onSave
        self.onDelete = onDelete
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

                if onDelete != nil {
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
            .alert("Delete Goal", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this goal?")
            }
            .sheet(isPresented: $showCalendarScheduler) {
                CalendarSchedulerSheet(
                    goalTitle: title,
                    goalNotes: notes,
                    goalTargetDate: hasTargetDate ? targetDate : nil
                ) { msg in
                    scheduleMessage = msg
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
