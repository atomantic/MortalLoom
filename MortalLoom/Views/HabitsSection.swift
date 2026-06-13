import SwiftUI

// MARK: - HabitTab

/// Tabs on the Habits page: user-authored habits plus the built-in alcohol /
/// nicotine / sauna trackers. The raw values intentionally mirror
/// `SubstanceTab` so a `HabitTab` can round-trip to a `SubstanceTab` via
/// `SubstanceTab(rawValue: tab.rawValue)`.
enum HabitTab: String, CaseIterable, Hashable {
    case myHabits = "My Habits"
    case alcohol = "Alcohol"
    case nicotine = "Nicotine"
    case sauna = "Sauna"

    /// `SubstanceTab` counterpart for the built-in tracker tabs. `nil` for
    /// `.myHabits` since user-authored habits aren't a substance.
    var substance: SubstanceTab? {
        SubstanceTab(rawValue: rawValue)
    }

    static let selectedKey = "habits.selectedTab"
    static let showAlcoholKey = "habits.showAlcohol"
    static let showNicotineKey = "habits.showNicotine"
    static let showSaunaKey = "habits.showSauna"
}

// MARK: - HabitsPage

/// Top-level Habits page. Tabbed so the user lands back on whichever tracker
/// they used last. Built-in trackers can be hidden via Settings.
struct HabitsPage: View {
    @AppStorage(HabitTab.selectedKey) private var selectedTab: HabitTab = .myHabits
    @AppStorage(HabitTab.showAlcoholKey) private var showAlcohol: Bool = true
    @AppStorage(HabitTab.showNicotineKey) private var showNicotine: Bool = true
    @AppStorage(HabitTab.showSaunaKey) private var showSauna: Bool = true

    private var visibleTabs: [HabitTab] {
        var tabs: [HabitTab] = [.myHabits]
        if showAlcohol { tabs.append(.alcohol) }
        if showNicotine { tabs.append(.nicotine) }
        if showSauna { tabs.append(.sauna) }
        return tabs
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if visibleTabs.count > 1 {
                    tabPicker
                }

                switch selectedTab {
                case .myHabits:
                    HabitsSection()
                case .alcohol:
                    SubstancesView(selectedTab: .alcohol)
                case .nicotine:
                    SubstancesView(selectedTab: .nicotine)
                case .sauna:
                    SubstancesView(selectedTab: .sauna)
                }
            }
            .padding(.vertical)
        }
        .background(Color.bg)
        .task {
            applyLaunchArg()
            clampToVisibleTab()
        }
        .onChange(of: visibleTabs) { _, _ in
            clampToVisibleTab()
        }
    }

    private var tabPicker: some View {
        Picker("Habit Tab", selection: $selectedTab) {
            ForEach(visibleTabs, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private func applyLaunchArg() {
        guard let arg = AppConstants.startHabitTab,
              let tab = HabitTab.allCases.first(where: { $0.rawValue.lowercased() == arg }),
              tab != selectedTab else { return }
        selectedTab = tab
    }

    /// Drop back to My Habits if the persisted tab was just hidden in Settings.
    private func clampToVisibleTab() {
        guard !visibleTabs.contains(selectedTab) else { return }
        selectedTab = .myHabits
    }
}

// MARK: - HabitsSection

/// Custom-habit tracker — the body content of the Habits page.
/// Shows Habitica-style cards with streak, cadence, and a tap-to-complete action.
/// Precomputed per-habit stats. Cached in loadData so we don't re-run the
/// streak/hit-rate loops on every body render.
struct HabitStats: Sendable {
    let streak: Int
    let hitRate30d: Double
    let todayCount: Int
}

struct HabitsSection: View {
    @State private var habits: [Habit] = []
    @State private var goals: [Goal] = []
    @State private var habitStats: [UUID: HabitStats] = [:]
    @State private var editingHabit: Habit?
    @State private var showingAdd = false
    @State private var toastMessage: String?
    @State private var confirmDelete: Habit?
    @State private var apexGoal: Goal?
    @State private var showDailyNudge = false
    /// Rate-limits the daily nudge to once per calendar day. The stored
    /// value is a `YYYY-MM-DD` string so it auto-resets at midnight without
    /// any explicit clearing.
    static let dailyNudgeDismissedOnKey = "habits.dailyNudgeDismissedOn"
    @AppStorage(Self.dailyNudgeDismissedOnKey) private var nudgeDismissedOn: String = ""

    var body: some View {
        VStack(spacing: 12) {
            header

            if habits.isEmpty {
                emptyState
            } else {
                ForEach(activeHabits) { habit in
                    habitCard(habit)
                }

                if !archivedHabits.isEmpty {
                    archivedSection
                }
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
        .sheet(isPresented: $showingAdd) {
            HabitEditSheet(habit: nil, goals: goals) { newHabit in
                Task {
                    await DataStore.shared.addHabit(newHabit)
                    await loadData()
                }
            }
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditSheet(habit: habit, goals: goals, onSave: { updated in
                Task {
                    await DataStore.shared.updateHabit(updated)
                    await loadData()
                }
            }, onDelete: {
                confirmDelete = habit
            })
        }
        .alert("Delete habit?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let h = confirmDelete {
                    Task {
                        await DataStore.shared.removeHabit(id: h.id)
                        await loadData()
                    }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This removes the habit and all its completions.")
        }
        .overlay(alignment: .top) {
            if let msg = toastMessage {
                ToastView(message: msg)
            }
        }
        .overlay(alignment: .bottom) {
            if showDailyNudge, let apex = apexGoal {
                DailyNudgeCard(
                    apexTitle: apex.title,
                    onRate: { logNudgeReflection(apex: apex, rating: $0) },
                    onDismiss: dismissNudge
                )
                .padding(.horizontal)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showDailyNudge)
    }

    // MARK: Data loading

    private func loadData() async {
        let data = await DataStore.shared.getData()
        habits = data.habits
        goals = data.goals
        apexGoal = data.goals.activeApex
        let now = Date()
        var stats: [UUID: HabitStats] = [:]
        for h in data.habits where h.isActive {
            stats[h.id] = HabitStats(
                streak: HabitEngine.currentStreak(h, now: now),
                hitRate30d: HabitEngine.targetHitRate(h, windowDays: 30, now: now),
                todayCount: HabitEngine.completionsInPeriod(h, containing: now)
            )
        }
        habitStats = stats
    }

    private func apexNeedsReflectionToday() -> Bool {
        guard let apex = apexGoal else { return false }
        let today = DateFormatting.todayString()
        return !apex.checkIns.contains { $0.isReflection && $0.date == today }
    }

    private func logNudgeReflection(apex: Goal, rating: Int) {
        var updated = apex
        updated.checkIns.append(GoalCheckIn(
            progressPct: 0,
            note: "",
            alignmentRating: rating,
            promptAnswered: ReflectionPrompts.dailyNudge
        ))
        Task {
            await DataStore.shared.updateGoal(updated)
            await loadData()
        }
        dismissNudge()
    }

    private func dismissNudge() {
        nudgeDismissedOn = DateFormatting.todayString()
        showDailyNudge = false
    }

    private var activeHabits: [Habit] {
        habits.filter { $0.isActive }
    }

    private var archivedHabits: [Habit] {
        habits.filter { !$0.isActive }
    }

    // MARK: Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("My Habits")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("Daily engagement for your goals")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            Button {
                showingAdd = true
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 44))
                .foregroundColor(.textMuted)
            Text("No habits yet")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("Habits are the daily actions that move you toward your goals — writing, meditation, exercise, reading. Link each one to a goal or life pillar so its streak health contributes to your alignment score.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Button {
                showingAdd = true
            } label: {
                Label("Add your first habit", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(LinearGradient.proBrand)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        // Hero glyph is a fixed 44pt; cap the surrounding copy's Dynamic Type
        // growth so the empty state stays balanced at AX sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .cardStyle()
    }

    private func habitCard(_ habit: Habit) -> some View {
        let stats = habitStats[habit.id] ?? HabitStats(streak: 0, hitRate30d: 0, todayCount: 0)
        let streak = stats.streak
        let hitRate = stats.hitRate30d
        let todayCount = stats.todayCount
        let target = habit.cadence.target
        let hitToday = todayCount >= target

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                habitIcon(habit)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 6) {
                        Text(habit.cadence.label)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        if habit.kind == .negative {
                            Text("• Break")
                                .font(.caption)
                                .foregroundColor(.warning)
                        }
                    }
                    if let parentId = habit.parentGoalId,
                       let parent = goals.first(where: { $0.id == parentId }) {
                        HStack(spacing: 4) {
                            Image(systemName: parent.goalType?.icon ?? "target")
                                .font(.caption2)
                            Text(parent.title)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundColor(.accentColor)
                    }
                }

                Spacer()

                completeButton(habit, hitToday: hitToday, todayCount: todayCount, target: target)
            }

            HStack(spacing: 14) {
                statChip(icon: "flame.fill", value: "\(streak)", label: streak == 1 ? "day" : "days", color: streak > 0 ? .orange : .textMuted)
                statChip(icon: "chart.line.uptrend.xyaxis", value: "\(Int(hitRate))%", label: "30d", color: .accentColor)
                if target > 1 {
                    statChip(icon: "target", value: "\(todayCount)/\(target)", label: "today", color: hitToday ? .success : .textMuted)
                }
                Spacer()
            }
        }
        .padding()
        .cardStyle()
        .contextMenu {
            Button {
                editingHabit = habit
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmDelete = habit
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onTapGesture { editingHabit = habit }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the habit editor")
    }

    private func habitIcon(_ habit: Habit) -> some View {
        ZStack {
            Circle()
                .fill(habit.color.opacity(0.15))
                .frame(width: 44, height: 44)
            Image(systemName: habit.icon)
                .font(.title3)
                .foregroundColor(habit.color)
        }
    }

    private func completeButton(_ habit: Habit, hitToday: Bool, todayCount: Int, target: Int) -> some View {
        Button {
            completeHabit(habit)
        } label: {
            ZStack {
                Circle()
                    .fill(hitToday ? Color.success : Color.bgInput)
                    .frame(width: 44, height: 44)
                Image(systemName: hitToday ? "checkmark" : "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(hitToday ? .white : .accentColor)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hitToday ? "\(habit.name) complete for today" : "Complete \(habit.name)")
    }

    private func statChip(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(value)
                .font(.caption).fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "ARCHIVED")
            ForEach(archivedHabits) { habit in
                HStack {
                    Image(systemName: habit.icon)
                        .foregroundColor(.textMuted)
                    Text(habit.name)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(habit.completions.count) completions")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
                .padding(10)
                .cardStyle()
                .onTapGesture { editingHabit = habit }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the habit editor")
            }
        }
    }

    // MARK: Actions

    private func completeHabit(_ habit: Habit) {
        let todayStr = DateFormatting.todayString()
        let completion = HabitCompletion(date: todayStr, count: 1, note: "")
        Task {
            await DataStore.shared.logHabitCompletion(habitId: habit.id, completion: completion)
            await loadData()
            await MainActor.run {
                toastMessage = "\(habit.name) ✓"
                if apexGoal != nil
                    && apexNeedsReflectionToday()
                    && nudgeDismissedOn != todayStr {
                    showDailyNudge = true
                }
            }
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { toastMessage = nil }
        }
    }
}

// MARK: - DailyNudgeCard

/// Three-tap reflection card shown after a habit completion — Yes / Partially /
/// No map to alignment ratings 8 / 5 / 2. Rate-limited to once per calendar day
/// via `HabitsSection.nudgeDismissedOn`.
private struct DailyNudgeCard: View {
    let apexTitle: String
    let onRate: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text("Daily check")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .tracking(1)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                        .padding(6)
                        .background(Color.bgInput)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss daily check")
            }

            Text("Did today move toward \(apexTitle)?")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                nudgeButton(label: "Yes", rating: 8, color: .success)
                nudgeButton(label: "Partially", rating: 5, color: .warning)
                nudgeButton(label: "No", rating: 2, color: .danger)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(border: .accentColor.opacity(0.3))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    private func nudgeButton(label: String, rating: Int, color: Color) -> some View {
        Button { onRate(rating) } label: {
            Text(label)
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(color.opacity(0.12))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HabitEditSheet

struct HabitEditSheet: View {
    let habit: Habit?
    let goals: [Goal]
    let onSave: (Habit) -> Void
    let onDelete: (() -> Void)?
    /// Non-nil when this sheet was opened to accept a `GenomeAction`. The
    /// banner appears at the top and the evidence is attached on save. The
    /// sheet treats this as a "new" form (no archive/delete sections,
    /// "Suggested Habit" title) regardless of whether `habit` is nil.
    let prefillEvidence: GeneticEvidence?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var detail: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var category: HabitCategory
    @State private var kind: HabitKind
    @State private var cadencePeriod: HabitCadencePeriod
    @State private var cadenceTarget: Int
    @State private var parentGoalId: UUID?
    @State private var archived: Bool

    /// True when this sheet is editing an existing saved habit (vs creating
    /// a new one, even one prefilled from a genome action).
    private var isEditingExisting: Bool { habit != nil && prefillEvidence == nil }

    /// Provenance shown on the banner. Prefer the prefill payload (a fresh
    /// suggestion in flight) over an already-saved habit's stored evidence —
    /// they refer to the same finding and the prefill text is canonical.
    private var displayEvidence: GeneticEvidence? {
        prefillEvidence ?? habit?.geneticEvidence
    }

    init(
        habit: Habit?,
        goals: [Goal],
        prefillEvidence: GeneticEvidence? = nil,
        onSave: @escaping (Habit) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.habit = habit
        self.goals = goals
        self.prefillEvidence = prefillEvidence
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: habit?.name ?? "")
        _detail = State(initialValue: habit?.detail ?? "")
        _icon = State(initialValue: habit?.icon ?? "checkmark.circle")
        _colorHex = State(initialValue: habit?.colorHex ?? "#4C8BF5")
        _category = State(initialValue: habit?.category ?? .general)
        _kind = State(initialValue: habit?.kind ?? .positive)
        _cadencePeriod = State(initialValue: habit?.cadence.period ?? .daily)
        _cadenceTarget = State(initialValue: habit?.cadence.target ?? 1)
        _parentGoalId = State(initialValue: habit?.parentGoalId)
        _archived = State(initialValue: habit?.archivedDate != nil)
    }

    private let iconOptions: [String] = [
        "checkmark.circle", "pencil", "book", "music.note",
        "figure.run", "heart.fill", "leaf.fill", "brain.head.profile",
        "paintbrush", "guitars", "camera", "moon.stars",
        "fork.knife", "drop.fill", "dumbbell", "flame.fill"
    ]

    private let colorOptions: [String] = [
        "#4C8BF5", "#8B5CF6", "#EC4899", "#EF4444",
        "#F59E0B", "#10B981", "#06B6D4", "#6366F1"
    ]

    private var parentCandidates: [Goal] {
        goals.filter { $0.status == .active }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let evidence = displayEvidence {
                    Section {
                        GeneticEvidenceBanner(evidence: evidence, dismiss: dismiss)
                    }
                }

                Section("Habit") {
                    TextField("Name (e.g. Write 500 words)", text: $name)
                    TextField("Notes (optional)", text: $detail, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Icon & Color") {
                    iconPicker
                    colorPicker
                }

                Section("Type") {
                    Picker("Build or Break", selection: $kind) {
                        ForEach(HabitKind.allCases, id: \.self) { k in
                            Label(k.label, systemImage: k.icon).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Category", selection: $category) {
                        ForEach(HabitCategory.allCases, id: \.self) { c in
                            Label(c.label, systemImage: c.icon).tag(c)
                        }
                    }
                }

                Section("Cadence") {
                    Picker("Period", selection: $cadencePeriod) {
                        Text("Daily").tag(HabitCadencePeriod.daily)
                        Text("Weekly").tag(HabitCadencePeriod.weekly)
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $cadenceTarget, in: 1...30) {
                        HStack {
                            Text(cadencePeriod == .daily ? "Times per day" : "Times per week")
                            Spacer()
                            Text("\(cadenceTarget)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Link to goal") {
                    Picker("Parent goal", selection: $parentGoalId) {
                        Text("None").tag(UUID?.none)
                        ForEach(parentCandidates, id: \.id) { g in
                            Text(g.title).tag(UUID?.some(g.id))
                        }
                    }
                    Text("Linked habits contribute to the alignment score of their parent goal or life pillar.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if isEditingExisting {
                    Section("Archive") {
                        Toggle("Archived", isOn: $archived)
                        Text("Archived habits stop contributing to alignment but keep their history.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if onDelete != nil {
                        Section {
                            Button(role: .destructive) {
                                onDelete?()
                                dismiss()
                            } label: {
                                Label("Delete Habit", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .macGroupedFormStyle()
            .navigationTitle(prefillEvidence != nil ? "Suggested Habit" : (habit == nil ? "New Habit" : "Edit Habit"))
            .inlineNavigationTitle()
            .macSheetFrame()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var iconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(iconOptions, id: \.self) { option in
                    Button {
                        icon = option
                    } label: {
                        Image(systemName: option)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(icon == option ? Color.accentColor.opacity(0.2) : Color.bgInput)
                            .foregroundColor(icon == option ? .accentColor : .textSecondary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(colorOptions, id: \.self) { hex in
                Button {
                    colorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? .accentColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(colorHex == hex ? Color.textPrimary : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func save() {
        // For prefilled-suggested flow, always create a fresh Habit (don't
        // reuse the prefill habit's id) so saving doesn't accidentally
        // overwrite a real existing habit.
        var result: Habit
        if isEditingExisting, let h = habit {
            result = h
        } else {
            result = Habit(name: name)
            if let evidence = prefillEvidence {
                result.geneticEvidence = evidence
            }
        }
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.detail = detail.trimmingCharacters(in: .whitespaces)
        result.icon = icon
        result.colorHex = colorHex
        result.category = category
        result.kind = kind
        result.cadence = HabitCadence(period: cadencePeriod, target: cadenceTarget)
        result.parentGoalId = parentGoalId
        if archived && result.archivedDate == nil {
            result.archivedDate = DateFormatting.todayString()
        } else if !archived {
            result.archivedDate = nil
        }
        onSave(result)
        dismiss()
    }
}

// MARK: - Toast

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline).fontWeight(.semibold)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.textPrimary.opacity(0.9))
            .foregroundColor(.bg)
            .cornerRadius(20)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
