import SwiftUI

// MARK: - GoalsView

struct GoalsView: View {
    /// All derived state computed in one pure pass by `GoalEngine`. The view
    /// itself does no business logic — it renders this value and re-flattens
    /// the tree on collapse/expand.
    @State private var vm = GoalEngine.GoalsViewModel()

    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var checkInGoal: Goal?
    @State private var pillarDashboardGoal: Goal?

    @State private var hierarchyItems: [GoalEngine.HierarchyItem] = []
    @State private var collapsedIds: Set<UUID> = []

    /// Goal id requested via `.openGoalReflect` (widget tap-through / deep
    /// link) before `vm.goals` finished loading. Resolved at the end of
    /// `loadData()` so a cold-launch widget tap still opens the sheet.
    @State private var pendingReflectGoalId: UUID?

    private static let treeLineColor = Color.textMuted.opacity(0.4)
    private static let treeLineWidth: CGFloat = 1.5
    private static let treeColumnWidth: CGFloat = 24

    private typealias HierarchyItem = GoalEngine.HierarchyItem

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
                allGoals: vm.goals,
                allHabits: vm.habits,
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
                allGoals: vm.goals,
                allHabits: vm.habits,
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
                allGoals: vm.goals,
                stagnationSignal: vm.signalByGoalId[goal.id]
            ) { updated in
                saveAndReload { await DataStore.shared.updateGoal(updated) }
            }
        }
        .sheet(item: $pillarDashboardGoal) { pillar in
            NavigationStack {
                PillarDashboardView(
                    pillar: pillar,
                    allGoals: vm.goals,
                    allHabits: vm.habits,
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
            if let goal = vm.goals.first(where: { $0.id == id }) {
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
        let model = GoalEngine.buildGoalsViewModel(from: data)
        vm = model
        hierarchyItems = GoalEngine.buildHierarchy(
            roots: model.roots,
            activeByParent: model.activeByParent,
            collapsedIds: collapsedIds
        )

        if let pending = pendingReflectGoalId,
           let goal = vm.goals.first(where: { $0.id == pending }) {
            pendingReflectGoalId = nil
            checkInGoal = goal
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
                    if let dc = vm.deathClock {
                        let years = String(format: "%.1f", dc.healthyYearsRemaining)
                        let label = if let lev = vm.levDeathClock {
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
                    Text("\(vm.activeCount) active")
                        .font(.caption).foregroundColor(.textSecondary)
                    Text("\(vm.completedCount) completed")
                        .font(.caption).foregroundColor(.success)
                    if vm.attentionCount > 0 {
                        Text("\(vm.attentionCount) need attention")
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
        if let apex = vm.apexGoal {
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

            let count = vm.childCounts[goal.id] ?? 0
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

        if hierarchyItems.isEmpty && vm.apexGoal == nil {
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
        let count = vm.childCounts[id] ?? 0
        return Button {
            if isCollapsed {
                collapsedIds.remove(id)
            } else {
                collapsedIds.insert(id)
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                hierarchyItems = GoalEngine.buildHierarchy(
                    roots: vm.roots,
                    activeByParent: vm.activeByParent,
                    collapsedIds: collapsedIds
                )
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
        if !vm.doneGoals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "COMPLETED")
                ForEach(vm.doneGoals) { goal in
                    goalCard(goal)
                }
            }
        }
    }

    // MARK: - Goal Card

    private func goalCard(_ goal: Goal) -> some View {
        let isLifelong = goal.goalType == .subApex
        let projection = vm.projections[goal.id] ?? GoalEngine.project(
            goal: goal, deathDate: vm.deathClock?.deathDate, healthyCognitiveDate: vm.cognitiveDeadline
        )
        let goalNeedsCheckIn = vm.effectiveNeedsCheckInIds.contains(goal.id)

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
                    urgencyBadge(projection.urgencyLevel, status: goal.status, isDeferred: goal.isDeferred())
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
                let count = vm.childCounts[goal.id] ?? 0
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

    private func urgencyBadge(_ urgency: GoalEngine.UrgencyLevel, status: GoalStatus, isDeferred: Bool = false) -> some View {
        let (text, color): (String, Color) = {
            if status == .completed { return ("Done", .success) }
            if isDeferred { return ("Snoozed", .accentColor) }
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
