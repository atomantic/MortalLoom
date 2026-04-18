import SwiftUI

// MARK: - GoalsView

struct GoalsView: View {
    @State private var goals: [Goal] = []
    @State private var habits: [Habit] = []
    @State private var deathClock: DeathClockEngine.DeathClockResult?
    @State private var levDeathClock: DeathClockEngine.DeathClockResult?
    @State private var projections: [UUID: GoalEngine.GoalProjection] = [:]
    @State private var cognitiveDeadline: Date?
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var checkInGoal: Goal?
    @State private var pillarDashboardGoal: Goal?

    @State private var apexGoal: Goal?
    @State private var hierarchyItems: [HierarchyItem] = []
    @State private var childCounts: [UUID: Int] = [:]
    @State private var doneGoals: [Goal] = []
    @State private var activeCount = 0
    @State private var completedCount = 0
    @State private var attentionCount = 0
    /// Per-goal stagnation signal (if any) — used to inject the suggested
    /// prompt at the top of CheckInSheet when opening a stale goal.
    @State private var signalByGoalId: [UUID: StagnationSignal] = [:]
    /// Parent goals inherit credit from any active descendant's recent
    /// check-in — prevents nag badges when sub-goals are being worked.
    @State private var effectiveNeedsCheckInIds: Set<UUID> = []

    // Cached for reflatten without full reload
    @State private var cachedRoots: [Goal] = []
    @State private var cachedActiveByParent: [UUID?: [Goal]] = [:]

    /// Goal id requested via `.openGoalReflect` (widget tap-through / deep
    /// link) before `goals` finished loading. Resolved at the end of
    /// `loadData()` so a cold-launch widget tap still opens the sheet.
    @State private var pendingReflectGoalId: UUID?

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
            GoalEditSheet(
                goal: nil,
                allGoals: goals,
                onSave: { newGoal in
                    saveAndReload { await DataStore.shared.addGoal(newGoal) }
                },
                onAddChild: { newChild in
                    saveAndReload { await DataStore.shared.addGoal(newChild) }
                }
            )
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditSheet(
                goal: goal,
                allGoals: goals,
                onSave: { updated in
                    saveAndReload { await DataStore.shared.updateGoal(updated) }
                },
                onDelete: {
                    saveAndReload { await DataStore.shared.removeGoal(id: goal.id) }
                },
                onAddChild: { newChild in
                    saveAndReload { await DataStore.shared.addGoal(newChild) }
                }
            )
        }
        .sheet(item: $checkInGoal) { goal in
            CheckInSheet(
                goal: goal,
                stagnationSignal: signalByGoalId[goal.id]
            ) { updated in
                saveAndReload { await DataStore.shared.updateGoal(updated) }
            }
        }
        .sheet(item: $pillarDashboardGoal) { pillar in
            NavigationStack {
                PillarDashboardView(
                    pillar: pillar,
                    allGoals: goals,
                    allHabits: habits,
                    onEditGoal: { g in
                        pillarDashboardGoal = nil
                        DispatchQueue.main.async { editingGoal = g }
                    },
                    onReflect: { g in
                        pillarDashboardGoal = nil
                        DispatchQueue.main.async { checkInGoal = g }
                    },
                    onEditHabit: { _ in
                        // Habit edit from the pillar dashboard not yet wired —
                        // user can still manage habits from the Habits page.
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { pillarDashboardGoal = nil }
                    }
                }
            }
            .macSheetFrame()
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGoalReflect)) { notif in
            guard let id = notif.object as? UUID else { return }
            if let goal = goals.first(where: { $0.id == id }) {
                checkInGoal = goal
            } else {
                pendingReflectGoalId = id
            }
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

        // Precompute effective latest check-in dates once so parent goals
        // inherit freshness from sub-goal activity in both the projection
        // math (slippage) and the overdue nags (attention count, chips).
        let effectiveLatestDates = data.goals.effectiveLatestCheckInDates()

        var projs: [UUID: GoalEngine.GoalProjection] = [:]
        for goal in data.goals {
            let days = DateFormatting.daysSince(
                effectiveLatestDates[goal.id] ?? goal.createdDate
            )
            projs[goal.id] = GoalEngine.project(
                goal: goal,
                deathDate: dc?.deathDate,
                healthyCognitiveDate: cogDate,
                daysSinceLastCheckInOverride: days
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

        // StagnationEngine sorts most-severe first, so taking the first
        // hit per goalId naturally keeps the highest-severity signal.
        let signals = StagnationEngine.signals(
            goals: data.goals,
            habits: data.habits,
            deathDate: dc?.deathDate,
            healthyCognitiveDate: cogDate
        )
        var byGoal: [UUID: StagnationSignal] = [:]
        for s in signals {
            if let gid = s.goalId, byGoal[gid] == nil {
                byGoal[gid] = s
            }
        }

        goals = data.goals
        habits = data.habits
        deathClock = dc
        levDeathClock = levDc
        cognitiveDeadline = cogDate
        projections = projs
        apexGoal = apex
        childCounts = counts
        doneGoals = done
        activeCount = activeGoals.count
        completedCount = done.count { $0.status == .completed }
        var needsIds = Set<UUID>()
        for g in data.goals where g.status == .active {
            let days = DateFormatting.daysSince(effectiveLatestDates[g.id] ?? g.createdDate)
            if days >= g.checkInIntervalDays { needsIds.insert(g.id) }
        }
        if effectiveNeedsCheckInIds != needsIds {
            effectiveNeedsCheckInIds = needsIds
        }
        attentionCount = activeGoals.count { needsIds.contains($0.id) || $0.isOverdue }
        signalByGoalId = byGoal
        cachedRoots = roots
        cachedActiveByParent = activeByParent
        hierarchyItems = buildHierarchy(roots: roots, activeByParent: activeByParent)

        if let pending = pendingReflectGoalId,
           let goal = goals.first(where: { $0.id == pending }) {
            pendingReflectGoalId = nil
            checkInGoal = goal
        }
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
                Button {
                    checkInGoal = goal
                } label: {
                    Label("Reflect", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.warning.opacity(0.15))
                        .foregroundColor(.warning)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Text(goal.title)
                .font(.title3).fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !goal.notes.isEmpty {
                Text(goal.notes)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            classificationChips(for: goal)

            let count = childCounts[goal.id] ?? 0
            if count > 0 {
                Text("\(count) supporting goal\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }

            let reflectionCount = goal.checkIns.filter { $0.isReflection }.count
            if reflectionCount > 0 {
                Text("\(reflectionCount) reflection\(reflectionCount == 1 ? "" : "s")")
                    .font(.caption2)
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
        let goalNeedsCheckIn = effectiveNeedsCheckInIds.contains(goal.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                if !isLifelong {
                    priorityDot(goal.priority)
                }
                GoalsViewHelpers.goalTypeBadge(goal.goalType)
                Text(goal.title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    // At AX sizes, one-line truncation hides essential info.
                    // Let the title wrap — the row height grows with it.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if goalNeedsCheckIn || goal.isOverdue {
                    Image(systemName: "bell.badge.fill")
                        .font(.caption)
                        .foregroundColor(.warning)
                }
                // Inline one-tap check-in button for active standard goals.
                // Sub-apex/apex use their own Reflect affordances; completed
                // and abandoned goals have nothing to check in.
                if !isLifelong && goal.status == .active {
                    Button {
                        checkInGoal = goal
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .padding(6)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Check in to \(goal.title)")
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
                    .fixedSize(horizontal: false, vertical: true)
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

                    if goalNeedsCheckIn {
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
            // Sub-apex (life pillar) opens its drill-in dashboard.
            // Standard goals tap to check in; edit is available via context menu.
            if goal.goalType == .subApex {
                pillarDashboardGoal = goal
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
                if let cat = goal.category { GoalsViewHelpers.categoryChip(cat) }
                if let hz = goal.horizon { GoalsViewHelpers.horizonChip(hz) }
            }
        }
    }

    @ViewBuilder
    private func goalContextMenu(for goal: Goal, isLifelong: Bool) -> some View {
        if goal.status == .active {
            Button { checkInGoal = goal } label: {
                Label(isLifelong ? "Reflect" : "Check In",
                      systemImage: isLifelong ? "bubble.left.and.bubble.right" : "pencil.and.list.clipboard")
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
    let onAddChild: ((Goal) -> Void)?
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
        defaultGoalType: GoalType? = nil,
        defaultHorizon: GoalHorizon? = nil,
        defaultPriority: GoalPriority? = nil,
        defaultParentId: UUID? = nil,
        defaultCategory: GoalCategory? = nil,
        onSave: @escaping (Goal) -> Void,
        onDelete: (() -> Void)? = nil,
        onAddChild: ((Goal) -> Void)? = nil
    ) {
        self.goal = goal
        self.allGoals = allGoals
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
        _checkInInterval = State(initialValue: g?.checkInIntervalDays ?? 7)
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

                if goal != nil {
                    signalMutingSection
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
            .macGroupedFormStyle()
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
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
    private var currentSignalsForGoal: [StagnationSignal] {
        guard let goalId = goal?.id else { return [] }
        let all = StagnationEngine.signals(goals: allGoals, habits: [])
        return all.filter { $0.goalId == goalId }
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

        var result = goal ?? Goal(title: title)
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

    init(goal: Goal, stagnationSignal: StagnationSignal? = nil, onSave: @escaping (Goal) -> Void) {
        self.goal = goal
        self.stagnationSignal = stagnationSignal
        self.onSave = onSave
        _progressPct = State(initialValue: goal.progressPercent)
        _milestoneStates = State(initialValue: Dictionary(uniqueKeysWithValues: goal.milestones.map { ($0.id, $0.completed) }))
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
            }
        }
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
            }
            .listRowBackground(signal.severity.tintColor.opacity(0.08))
        }
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

// MARK: - Shared Chip Helpers

/// File-private chip builders shared between GoalsView and CheckInSheet so
/// the category/horizon/type badge styling doesn't drift between the list
/// card and the check-in header.
fileprivate enum GoalsViewHelpers {
    @ViewBuilder
    static func goalTypeBadge(_ goalType: GoalType?) -> some View {
        if let gt = goalType, gt != .standard {
            Image(systemName: gt.icon)
                .font(.caption2)
                .foregroundColor(gt == .apex ? .warning : .accentColor)
        }
    }

    static func categoryChip(_ cat: GoalCategory) -> some View {
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

    static func horizonChip(_ hz: GoalHorizon) -> some View {
        Text(hz.label)
            .font(.system(size: 10))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.textSecondary.opacity(0.12))
            .cornerRadius(4)
    }
}
