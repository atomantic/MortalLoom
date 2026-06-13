import SwiftUI
import Charts

struct OverviewView: View {
    @Binding var selectedTab: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Owns data loading and the multi-engine orchestration; the view binds to
    /// its published output (issue #23). UI-only state — section toggles, sheet
    /// presentation, chart selection, layout width — stays in the view.
    @State private var vm = OverviewViewModel()

    @State private var isVisible = false
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    @State private var showCitations = false
    @State private var showAddGoal = false
    @State private var editingGoal: Goal?
    @State private var showWeeklyReview = false
    @State private var selectedChartYear: Int?
    @AppStorage(HabitTab.selectedKey) private var habitsTab: HabitTab = .myHabits
    // Sections start collapsed so the first frame never flashes tall empty
    // "—" placeholders before data loads (a visible snap on launch). Once we
    // know a profile with a birth date exists, `loadData()` expands them a
    // single time so users with real data see their runway/health up front.
    @AppStorage("overview.runwaySectionExpanded") private var runwayExpanded: Bool = false
    @AppStorage("overview.healthSectionExpanded") private var healthExpanded: Bool = false
    // One-shot flag so we only apply the first-launch expansion on a given
    // device once; afterwards we leave the user's explicit choice alone.
    @AppStorage("overview.hasAppliedFirstLaunchSectionState") private var hasAppliedFirstLaunchSectionState: Bool = false
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }

    var body: some View {
        ScrollView {
            Group {
                if isWide {
                    wideContentStack
                } else {
                    narrowContentStack
                }
            }
            .padding()
            .readContainerWidth { containerWidth = $0 }
        }
        .background(Color.bg)
        .task { await loadData() }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
            Task { await loadData() }
        }
        .sheet(isPresented: $showCitations) { CitationsView() }
        .sheet(isPresented: $showAddGoal) {
            GoalEditSheet(
                goal: nil,
                allGoals: vm.data.goals,
                allHabits: vm.data.habits,
                defaultGoalType: .apex,
                defaultHorizon: .lifetime,
                defaultPriority: .high,
                defaultCategory: .legacy,
                onSave: { newGoal in
                    Task {
                        await DataStore.shared.addGoal(newGoal)
                        await loadData()
                    }
                },
                onAddChild: { newChild in
                    Task {
                        await DataStore.shared.addGoal(newChild)
                        await loadData()
                    }
                }
            )
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditSheet(
                goal: goal,
                allGoals: vm.data.goals,
                allHabits: vm.data.habits,
                onSave: { updated in
                    Task {
                        await DataStore.shared.updateGoal(updated)
                        await loadData()
                    }
                },
                onDelete: {
                    Task {
                        await DataStore.shared.removeGoal(id: goal.id)
                        await loadData()
                    }
                },
                onAddChild: { newChild in
                    Task {
                        await DataStore.shared.addGoal(newChild)
                        await loadData()
                    }
                }
            )
        }
        .sheet(isPresented: $showWeeklyReview) {
            WeeklyReviewSheet(
                apex: vm.apexGoal,
                allGoals: vm.data.goals,
                habits: vm.data.habits
            ) { updated in
                Task {
                    await DataStore.shared.updateGoal(updated)
                    await loadData()
                }
            }
        }
    }

    // Narrow and wide stacks share the same top-of-page (setup recovery,
    // goal prompt, weekly review CTA, attention card), the same health
    // summary section, and the same recommendations card. Only the runway
    // detail layout differs — wide puts death-clock and LE factors side
    // by side; narrow stacks them. The shared chunks live in
    // `topChromeStack` and `bottomChromeStack` so they only exist once.

    @ViewBuilder
    private var topChromeStack: some View {
        if needsSetupRecovery { finishSetupBanner }
        goalPromptCard
        // Cap stacked attention banners on narrow widths: finishSetup +
        // goalPrompt + weeklyReview + attention can be four full-width cards,
        // which on an iPhone SE pushes the primary "YOUR RUNWAY" content below
        // the fold. Wide layouts have the vertical room, so show both; narrow
        // shows only the single highest-priority secondary banner (stagnation
        // signals over the weekly-review nudge, since they're more actionable).
        if isWide {
            if WeeklyReview.isDue && vm.apexGoal != nil { weeklyReviewCTA }
            if !vm.cachedStagnationSignals.isEmpty { attentionCard }
        } else if !vm.cachedStagnationSignals.isEmpty {
            attentionCard
        } else if WeeklyReview.isDue && vm.apexGoal != nil {
            weeklyReviewCTA
        }

        // Runway strip — compact summary of time remaining, expandable
        // to the full longevity clock / LEV / factors detail.
        collapsibleHeader(
            title: "YOUR RUNWAY",
            subtitle: runwaySubtitle,
            expanded: $runwayExpanded
        )
    }

    @ViewBuilder
    private var bottomChromeStack: some View {
        // Health summary — vital stats + health grid. Collapsible for
        // users whose North Star doesn't touch health; they can still
        // open it on demand.
        collapsibleHeader(
            title: "HEALTH SUMMARY",
            subtitle: nil,
            expanded: $healthExpanded
        )
        if healthExpanded {
            vitalStatsRow
            healthGrid
        }

        if !vm.cachedRecommendations.isEmpty { recommendationsCard }
    }

    @ViewBuilder
    private var narrowContentStack: some View {
        VStack(spacing: 16) {
            topChromeStack
            if runwayExpanded {
                if let lev = vm.lev { levCard(lev) }
                deathClockCard
                if vm.deathClock != nil { lifeExpectancyFactorsCard }
                if let dc = vm.deathClock { lifetimeHealthChart(dc) }
            }
            bottomChromeStack
        }
    }

    /// True when the user has finished onboarding but lacks the key inputs
    /// that drive the longevity clock (birth date) — e.g. users who bailed
    /// out of the 13-step flow before the lifestyle questions. Shows a
    /// banner that offers to re-run the setup wizard without erasing data.
    private var needsSetupRecovery: Bool {
        vm.data.profile.birthDate == nil
    }

    @ViewBuilder
    private var finishSetupBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.warning)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("Finish your setup")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                Text("Your longevity clock needs your birth date and a few lifestyle answers to start ticking.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        UserDefaults.standard.set(false, forKey: AppConstants.hasCompletedOnboardingKey)
                        NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    } label: {
                        Text("Run setup wizard")
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    Button {
                        selectedTab = AppPage.lifestyle.rawValue
                    } label: {
                        Text("Open Lifestyle")
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding()
        .cardStyle(fill: .warning.opacity(0.08), border: .warning.opacity(0.25))
    }

    @ViewBuilder
    private var wideContentStack: some View {
        VStack(spacing: 16) {
            topChromeStack
            if runwayExpanded {
                if let lev = vm.lev { levCard(lev) }
                HStack(alignment: .top, spacing: 16) {
                    deathClockCard
                    if vm.deathClock != nil {
                        lifeExpectancyFactorsCard
                    }
                }
                if let dc = vm.deathClock {
                    lifetimeHealthChart(dc)
                        .frame(maxWidth: .infinity)
                }
            }
            bottomChromeStack
        }
    }

    /// A compact "remaining X years • LEV in Y" strip shown above the runway
    /// section when collapsed, so the user always sees the time framing even
    /// if they've hidden the detail.
    private var runwaySubtitle: String? {
        guard let dc = vm.deathClock else { return nil }
        let years = Int(dc.yearsRemaining)
        if years <= 0 { return nil }
        return "~\(years) years estimated remaining"
    }

    /// Reusable collapsible section header. Tapping the row toggles the
    /// binding. Chevron rotates smoothly for affordance.
    private func collapsibleHeader(
        title: String,
        subtitle: String?,
        expanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .tracking(1)
                if let subtitle {
                    Text("• \(subtitle)")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
                    .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
            }
            .contentShape(Rectangle())
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) section. \(expanded.wrappedValue ? "Expanded" : "Collapsed"). Tap to toggle.")
    }

    // MARK: - Weekly Review CTA

    @ViewBuilder
    private var weeklyReviewCTA: some View {
        Button {
            showWeeklyReview = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Review")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("5 minutes to reset alignment and plan the week")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.proBrand)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Attention card (Reports mirror)

    /// Compact "Attention Needed" card showing the top stagnation signals on
    /// the Overview. Mirrors the Reports page stagnation card but collapsed
    /// to a 2-row preview. Tapping jumps to Reports for the full list.
    @ViewBuilder
    private var attentionCard: some View {
        let topSignals = Array(vm.cachedStagnationSignals.prefix(3))
        Button {
            selectedTab = AppPage.reports.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .foregroundColor(.warning)
                    Text("ATTENTION NEEDED")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.warning)
                        .textCase(.uppercase)
                        .tracking(1)
                    Spacer()
                    Text("\(vm.cachedStagnationSignals.count)")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textMuted)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
                ForEach(topSignals) { signal in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: signal.severity.iconName)
                            .font(.caption2)
                            .foregroundColor(signal.severity.tintColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(signal.title)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.textPrimary)
                            Text(signal.detail)
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                Text(vm.cachedStagnationSignals.count > 3
                     ? "+\(vm.cachedStagnationSignals.count - 3) more — tap to review in Reports"
                     : "Tap to review in Reports")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .cardStyle(fill: .warning.opacity(0.06), border: .warning.opacity(0.2))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Reports to review and respond to these signals")
    }

    // MARK: - Data Loading

    /// View-side load: delegates data + engine orchestration to the view-model,
    /// then applies the first-launch section collapse (a UI-only preference the
    /// view owns).
    private func loadData() async {
        await vm.load()
        // First-launch section state: the sections default to collapsed so the
        // first frame doesn't flash tall empty "—" placeholders. Once data has
        // loaded, expand them a single time iff a profile with a birth date
        // exists — users with real data want their runway/health up front, while
        // brand-new users keep the collapsed CTA-forward screen. After this
        // one-shot we leave the user's explicit preference alone.
        if !hasAppliedFirstLaunchSectionState {
            let defaults = UserDefaults.standard
            let runwayKey = "overview.runwaySectionExpanded"
            let healthKey = "overview.healthSectionExpanded"
            // An install that already persisted a section preference (or the
            // legacy collapse flag) is an upgrade, not a first launch.
            let isExistingInstall =
                defaults.object(forKey: runwayKey) != nil
                || defaults.object(forKey: healthKey) != nil
                || defaults.object(forKey: "overview.hasCollapsedEmptySections") != nil
            if isExistingInstall {
                // Migrate per section. The @AppStorage default flipped true→false,
                // so an ABSENT key — which used to render as expanded — would now
                // silently collapse a section the user never touched. Seed each
                // missing key to the old expanded default to preserve behavior; a
                // section the user explicitly collapsed already has its key stored
                // (false) and is left exactly as they set it.
                if defaults.object(forKey: runwayKey) == nil { runwayExpanded = true }
                if defaults.object(forKey: healthKey) == nil { healthExpanded = true }
                hasAppliedFirstLaunchSectionState = true
            } else if vm.data.profile.birthDate != nil {
                // Fresh install with data available (typed during onboarding, or
                // arrived via iCloud restore): expand once so real runway/health
                // shows up front, then stop overriding the user's choice.
                runwayExpanded = true
                healthExpanded = true
                hasAppliedFirstLaunchSectionState = true
            }
            // else: fresh install whose profile hasn't loaded yet (e.g. the
            // first load happens under the onboarding cover, before a birth date
            // is saved). Leave the one-shot UNSET so a later reload — the
            // .profileDidChange that fires when onboarding saves the profile —
            // can still apply the expansion. Until then the collapsed defaults
            // stand, which is exactly the no-data first-launch screen we want.
        }
    }

    // MARK: - Goal Prompt Card

    @ViewBuilder
    private var goalPromptCard: some View {
        if let apex = vm.apexGoal {
            apexGoalCard(apex)
        } else {
            setGoalCard
        }
    }

    @ViewBuilder
    private func apexGoalCard(_ goal: Goal) -> some View {
        let alignment = alignmentScore(for: goal)
        let supportingCount = supportingGoalsCount(for: goal)
        let pillarCount = lifePillarCount(for: goal)
        let streak = vm.cachedReflectionStreak

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .font(.title3)
                Text("Your North Star")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.textSecondary)
                    .tracking(0.5)
                Spacer()
                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("\(streak)d")
                            .font(.caption2).fontWeight(.bold).monospacedDigit()
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
                    .accessibilityLabel("\(streak) day reflection streak")
                }
                Text("Lifetime")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }

            Text(goal.title)
                .font(.title3).fontWeight(.bold)
                .foregroundColor(.textPrimary)

            if !goal.notes.isEmpty {
                Text(goal.notes)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }

            // Alignment — how well recent concrete goals are tracking toward this North Star.
            // Unlike progress (which implies an end), alignment is ongoing: the average of
            // active standard descendants' progress percentages.
            if let score = alignment {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Alignment")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(String(format: "%.0f%%", score))
                            .font(.caption).monospacedDigit()
                            .foregroundColor(.accentColor)
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
                    Text("Average progress across your active supporting goals.")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            } else {
                Text("Add supporting goals to see how aligned your recent work is with this North Star.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            HStack(spacing: 12) {
                statPill(icon: "star.fill", value: "\(pillarCount)", label: pillarCount == 1 ? "pillar" : "pillars")
                statPill(icon: "target", value: "\(supportingCount)", label: supportingCount == 1 ? "goal" : "goals")
                statPill(icon: "circle.grid.2x2.fill", value: "\(vm.activeGoalCount)", label: "total")
            }

            if supportingCount == 0 {
                goalCTAButton(
                    icon: "plus.circle",
                    text: "Add a supporting goal",
                    background: AnyShapeStyle(LinearGradient.proBrandSubtleDiagonal)
                ) { editingGoal = goal }
            } else {
                goalCTAButton(
                    icon: "pencil.and.outline",
                    text: "Review supporting goals",
                    background: AnyShapeStyle(Color.accentColor.opacity(0.15))
                ) { editingGoal = goal }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func alignmentScore(for apex: Goal) -> Double? {
        vm.cachedApexAlignment
    }

    private func supportingGoalsCount(for apex: Goal) -> Int {
        GoalEngine.activeDescendants(of: apex, in: vm.data.goals).count
    }

    private func lifePillarCount(for apex: Goal) -> Int {
        vm.data.goals.filter { $0.parentId == apex.id && $0.goalType == .subApex && $0.status == .active }.count
    }

    @ViewBuilder
    private func goalCTAButton(
        icon: String,
        text: String,
        background: AnyShapeStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(text)
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(background)
            .foregroundColor(.accentColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var setGoalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .font(.title3)
                Text("Set Your North Star")
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Text("What\u{2019}s the one big thing you want to accomplish? Everything else builds toward it.")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("A North Star is broad and lifelong — not a project. Examples: live healthy as long as possible, leave a lasting creative legacy, raise a loving resilient family.")
                .font(.caption)
                .foregroundColor(.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showAddGoal = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Set My North Star Goal")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.proBrand)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private func statPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.textMuted)
            Text(value)
                .font(.caption).fontWeight(.bold).monospacedDigit()
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.bgInput)
        .cornerRadius(6)
    }

    // MARK: - Health Summary Hero Card

    @ViewBuilder
    private var deathClockCard: some View {
        VStack(spacing: 16) {
            if let dc = vm.activeDC {
                // Header
                HStack {
                    Image(systemName: "heart.text.clipboard")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                    Text("Health Summary")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Spacer()
                }

                // Health Score
                HStack {
                    Text("Health Score")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f / 100", vm.cachedHealthScore))
                        .font(.title2).fontWeight(.bold).monospacedDigit()
                        .foregroundColor(healthScoreColor(vm.cachedHealthScore))
                }

                Divider().background(Color.cardBorder)

                // Life expectancy breakdown
                VStack(alignment: .leading, spacing: 6) {
                    Text("Life Expectancy Breakdown")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    leBreakdownRow("SSA Baseline", value: dc.lifeExpectancy.baseline, unit: "yr")
                    leBreakdownRow("Genome Adjusted", value: dc.lifeExpectancy.genomeAdjusted, unit: "yr")
                    leBreakdownRow("Lifestyle Adj.", value: dc.lifeExpectancy.lifestyleAdjustment, unit: "yr", signed: true)
                    if dc.lifeExpectancy.locationAdjustment != 0 {
                        leBreakdownRow("Location Adj.", value: dc.lifeExpectancy.locationAdjustment, unit: "yr", signed: true)
                    }
                    if dc.lifeExpectancy.healthMetricsAdjustment != 0 {
                        leBreakdownRow("Health Metrics", value: dc.lifeExpectancy.healthMetricsAdjustment, unit: "yr", signed: true)
                    }
                    if dc.lifeExpectancy.socioeconomicAdjustment != 0 {
                        leBreakdownRow("Socioeconomic", value: dc.lifeExpectancy.socioeconomicAdjustment, unit: "yr", signed: true)
                    }
                    Divider().background(Color.cardBorder)
                    leBreakdownRow("Total LE", value: dc.lifeExpectancy.total, unit: "yr", bold: true)
                }

                Divider().background(Color.cardBorder)

                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Life Progress")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f%%", dc.percentComplete))
                            .font(.caption).monospacedDigit()
                            .foregroundColor(progressColor(dc.percentComplete))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.bgInput)
                                .frame(height: 10)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor(dc.percentComplete))
                                .frame(width: geo.size.width * min(1, dc.percentComplete / 100), height: 10)
                        }
                    }
                    .frame(height: 10)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Life progress")
                .accessibilityValue(String(format: "%.1f percent complete", dc.percentComplete))

                Button {
                    showCitations = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed.fill")
                            .font(.caption2)
                        Text("View Sources & Citations")
                            .font(.caption2).fontWeight(.medium)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                // Not configured
                VStack(spacing: 10) {
                    Image(systemName: "heart.text.clipboard")
                        .font(.largeTitle)
                        .foregroundColor(.textMuted)
                    Text("Health Summary")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Add your birth date and lifestyle to see your longevity clock, runway, and health summary.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        selectedTab = AppPage.lifestyle.rawValue
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.clipboard")
                            Text("Open Lifestyle")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    Button {
                        UserDefaults.standard.set(false, forKey: AppConstants.hasCompletedOnboardingKey)
                        NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    } label: {
                        Text("Or run the setup wizard")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    @ViewBuilder
    private func leBreakdownRow(_ label: String, value: Double, unit: String, signed: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .subheadline.weight(.semibold) : .caption)
                .foregroundColor(bold ? .textPrimary : .textSecondary)
            Spacer()
            Text(signed ? String(format: "%+.1f %@", value, unit) : String(format: "%.1f %@", value, unit))
                .font(bold ? .subheadline.weight(.bold).monospacedDigit() : .caption.monospacedDigit())
                .foregroundColor(bold ? .textPrimary : .textSecondary)
        }
    }

    private func progressColor(_ percent: Double) -> Color {
        if percent >= 80 { return .danger }
        if percent >= 60 { return .warning }
        return .blue
    }

    // MARK: - Life Expectancy Factors Card

    @ViewBuilder
    private var lifeExpectancyFactorsCard: some View {
        let lifestyle = vm.data.profile.lifestyle
        let metrics = vm.data.healthMetrics
        let cardioImpact = metrics.compactAverage(\.cardioRecovery).map { CardioFitnessEngine.recoveryLongevityImpact($0) } ?? 0.0
        let gaitImpact = metrics.compactAverage(\.walkingSpeed).map { GaitEngine.walkingSpeedLongevityImpact($0, age: vm.deathClock?.ageYears ?? 0) } ?? 0.0
        let apneaImpact = metrics.compactAverage(\.breathingDisturbances).map { SleepEngine.apneaLongevityImpact($0) } ?? 0.0

        let allFactors: [(name: String, icon: String, value: Double)] = [
            ("Genome", "dna", DeathClockEngine.genomeAdjustment(vm.data.genomeScanRecord)),
            ("Smoking", "nosign", DeathClockEngine.smokingImpact(lifestyle.smokingStatus)),
            ("Exercise", "figure.run", DeathClockEngine.exerciseImpact(lifestyle.exerciseMinutesPerWeek)),
            ("Sleep", "bed.double.fill", vm.cachedSleepImpact),
            ("Diet", "fork.knife", DeathClockEngine.dietImpact(lifestyle.dietQuality)),
            ("Stress", "brain.head.profile", DeathClockEngine.stressImpact(lifestyle.stressLevel)),
            ("BMI", "scalemass.fill", DeathClockEngine.bmiImpact(lifestyle.bmi)),
            ("Location", "globe", vm.deathClock?.lifeExpectancy.locationAdjustment ?? 0),
            ("Cardio Recovery", "heart.fill", cardioImpact),
            ("Walking Speed", "figure.walk", gaitImpact),
            ("Apnea Risk", "lungs.fill", apneaImpact),
        ]
        let factors = allFactors.filter { $0.value != 0 }

        if !factors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                    Text("Life Expectancy Factors")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    CitationBadge(
                        ids: [
                            CitationLibrary.ssaLifeTable.id,
                            CitationLibrary.whoLifeExpectancy.id,
                            CitationLibrary.dollSmoking2004.id,
                            CitationLibrary.cappuccioSleep2010.id,
                            CitationLibrary.whoPhysicalActivity.id,
                            CitationLibrary.arem2015Exercise.id,
                            CitationLibrary.predimedMedDiet.id,
                            CitationLibrary.epelTelomere2004.id,
                            CitationLibrary.bmiMortality2016.id,
                            CitationLibrary.niaaaLimits.id,
                            CitationLibrary.deelenApoe2019.id,
                            CitationLibrary.lancetPollution2018.id,
                        ],
                        claim: "Sources for every factor contributing to your life-expectancy estimate"
                    )
                }

                Text("How each factor affects your lifespan")
                    .font(.caption)
                    .foregroundColor(.textMuted)

                ForEach(factors, id: \.name) { factor in
                    factorRow(name: factor.name, icon: factor.icon, value: factor.value)
                }

                Divider().background(Color.cardBorder)

                let net = factors.reduce(0.0) { $0 + $1.value }
                HStack {
                    Image(systemName: "sum")
                        .foregroundColor(.textSecondary)
                        .font(.caption)
                        .frame(width: 20)
                    Text("Net Impact")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text(String(format: "%+.1f yr", net))
                        .font(.subheadline).fontWeight(.bold).monospacedDigit()
                        .foregroundColor(net > 0 ? .success : net < 0 ? .danger : .textSecondary)
                }

                if factors.count < allFactors.count {
                    Text("\(allFactors.count - factors.count) neutral factor\(allFactors.count - factors.count == 1 ? "" : "s") not shown")
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    @ViewBuilder
    private func factorRow(name: String, icon: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(value > 0 ? .success : .danger)
                .font(.caption)
                .frame(width: 20)
            Text(name)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 70, alignment: .leading)
            GeometryReader { geo in
                let maxAbsValue = 10.0 // scale: max |-10| for smoking
                let barWidth = abs(value) / maxAbsValue * geo.size.width * 0.7
                let isPositive = value > 0
                ZStack(alignment: .leading) {
                    Color.clear
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isPositive ? Color.success : Color.danger)
                        .frame(width: max(4, barWidth), height: 16)
                        .offset(x: isPositive ? geo.size.width * 0.35 : geo.size.width * 0.35 - barWidth)
                }
            }
            .frame(height: 16)
            .clipped()
            Text(String(format: "%+.1f yr", value))
                .font(.caption).fontWeight(.bold).monospacedDigit()
                .foregroundColor(value > 0 ? .success : .danger)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(String(format: "%+.1f", value)) years impact on life expectancy")
    }

    // MARK: - LEV Card

    @ViewBuilder
    private func levCard(_ lev: DeathClockEngine.LEVResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.shield.fill")
                    .foregroundColor(lev.onTrack ? .success : .warning)
                    .font(.title3)
                Text("Longevity Escape Velocity")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(lev.onTrack ? "On Track" : "At Risk")
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(lev.onTrack ? Color.success.opacity(0.2) : Color.warning.opacity(0.2))
                    .foregroundColor(lev.onTrack ? .success : .warning)
                    .cornerRadius(6)
                    .accessibilityLabel("LEV status: \(lev.onTrack ? "on track" : "at risk")")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                levStatItem("Years to LEV", value: "\(lev.yearsToLEV)")
                levStatItem("Age at LEV", value: "\(lev.ageAtLEV)")
                levStatItem("Margin", value: String(format: "%.1f yr", lev.adjustedLifeExpectancy - Double(lev.ageAtLEV)))
                levStatItem("Adjusted LE", value: String(format: "%.1f yr", lev.adjustedLifeExpectancy))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // A one-off value-above-label readout used only in the LEV row; intentionally
    // kept local rather than folded into StatCell (which is label-above-value),
    // since generalizing for a single call site would add single-use parameters.
    @ViewBuilder
    private func levStatItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline).monospacedDigit()
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Lifetime Health Chart

    @ViewBuilder
    private func lifetimeHealthChart(_ dc: DeathClockEngine.DeathClockResult) -> some View {
        let currentYear = Calendar.current.component(.year, from: Date())
        let birthYear = currentYear - dc.ageYears
        let deathYear = birthYear + Int(dc.lifeExpectancy.total)
        let levYear = DeathClockEngine.Constants.levTargetYear
        let levDeathYear = birthYear + Int(DeathClockEngine.Constants.levTargetAge)

        let chartEndYear = levDeathYear + 1

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Health Trajectory")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(String(format: "%.0f%%", vm.cachedHealthScore))
                    .font(.headline).fontWeight(.bold).monospacedDigit()
                    .foregroundColor(healthScoreColor(vm.cachedHealthScore))
            }

            ZStack(alignment: .topLeading) {
            Chart {
                // Normal expected trajectory (now → life expectancy)
                ForEach(vm.cachedNormalPoints) { pt in
                    LineMark(
                        x: .value("Year", pt.year),
                        y: .value("Health", pt.health),
                        series: .value("Series", pt.series.rawValue)
                    )
                    .foregroundStyle(Color.warning)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // LEV optimistic trajectory
                ForEach(vm.cachedLevPoints) { pt in
                    LineMark(
                        x: .value("Year", pt.year),
                        y: .value("Health", pt.health),
                        series: .value("Series", pt.series.rawValue)
                    )
                    .foregroundStyle(Color.success)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [8, 4]))
                    .interpolationMethod(.catmullRom)
                }

                // "Now" dot
                PointMark(
                    x: .value("Year", currentYear),
                    y: .value("Health", vm.cachedHealthScore)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(80)

                // LEV vertical dashed line
                RuleMark(x: .value("LEV", levYear))
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .top, alignment: .center) {
                        Text("LEV")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.purple)
                    }

                // Life expectancy marker
                RuleMark(x: .value("LE", deathYear))
                    .foregroundStyle(Color.danger.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .center) {
                        Text("LE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.danger.opacity(0.6))
                    }

                // Selection indicator
                if let yr = selectedChartYear {
                    RuleMark(x: .value("Selected", yr))
                        .foregroundStyle(Color.textMuted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXSelection(value: $selectedChartYear)
            .chartXAxis {
                AxisMarks(values: .stride(by: 20)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.cardBorder)
                    AxisValueLabel(anchor: .top) {
                        if let v = value.as(Int.self) {
                            VStack(spacing: 1) {
                                Text("'\(String(format: "%02d", v % 100))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.textMuted)
                                Text("\(v - birthYear)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.textMuted.opacity(0.7))
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.cardBorder)
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)%")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...105)
            .chartXScale(domain: currentYear...chartEndYear)
            .chartLegend(.hidden)
            .frame(height: 220)

            // Floating tooltip overlay
            if let yr = selectedChartYear {
                let age = yr - birthYear
                let normal = vm.cachedNormalPoints.first(where: { $0.year == yr })?.health
                let lev = vm.cachedLevPoints.first(where: { $0.year == yr })?.health
                HStack(spacing: 10) {
                    Text("\(yr)")
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundColor(.textPrimary)
                    Text("Age \(age)")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                    if let n = normal {
                        HStack(spacing: 3) {
                            Circle().fill(Color.warning).frame(width: 5, height: 5)
                            Text(String(format: "%.0f%%", n))
                                .font(.caption.weight(.bold)).monospacedDigit()
                                .foregroundColor(.warning)
                        }
                    }
                    if let l = lev {
                        HStack(spacing: 3) {
                            Circle().fill(Color.success).frame(width: 5, height: 5)
                            Text(String(format: "%.0f%%", l))
                                .font(.caption.weight(.bold)).monospacedDigit()
                                .foregroundColor(.success)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.bgCard.opacity(0.95))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cardBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .padding(.top, 4)
                .padding(.leading, 30)
            }
            } // ZStack

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .warning, label: "Expected")
                legendItem(color: .success, label: "LEV Path", dashed: true)
            }
            .font(.system(size: 10))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health trajectory chart. Current health score \(String(format: "%.0f", vm.cachedHealthScore)) percent. Shows expected decline and LEV optimistic path from \(currentYear) to \(levDeathYear)")
    }

    private func healthScoreColor(_ score: Double) -> Color {
        if score >= 75 { return .success }
        if score >= 50 { return .warning }
        return .danger
    }

    @ViewBuilder
    private func legendItem(color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            if dashed {
                HStack(spacing: 2) {
                    Rectangle().fill(color).frame(width: 4, height: 2)
                    Rectangle().fill(color).frame(width: 4, height: 2)
                    Rectangle().fill(color).frame(width: 4, height: 2)
                }
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 14, height: 2)
            }
            Text(label)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Vital Stats Row

    @ViewBuilder
    private var vitalStatsRow: some View {
        let dc = vm.activeDC
        HStack(spacing: 12) {
            vitalBadge(
                value: dc.map { "\($0.ageYears)" } ?? "--",
                label: "Current Age",
                icon: "person.fill",
                tint: .blue
            )
            vitalBadge(
                value: dc.map { String(format: "%.1f", $0.yearsRemaining) } ?? "--",
                label: "Years Left",
                icon: "hourglass",
                tint: vm.countdownMode == .lev ? .success : .accentColor
            )
            vitalBadge(
                value: dc.map { String(format: "%.1f", $0.healthyYearsRemaining) } ?? "--",
                label: "Healthy Years",
                icon: "heart.fill",
                tint: .success
            )
        }
    }

    private func vitalBadge(value: String, label: String, icon: String, tint: Color) -> StatBadge {
        StatBadge(value: value, label: label, icon: icon, tint: tint, size: .prominent, accessibilityText: "\(label): \(value)")
    }

    // MARK: - Health Summary Grid

    @ViewBuilder
    private var healthGrid: some View {
        let columns = isWide
            ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        // No local title here — the section already has a collapsible
        // "HEALTH SUMMARY" header above this grid.
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 12) {
                alcoholTile
                bodyTile
                bloodTile
                epigeneticTile
                eyesTile
                lifestyleTile
            }
        }
    }

    // MARK: - Alcohol Tile

    @ViewBuilder
    private var alcoholTile: some View {
        let todayDrinks = vm.data.alcoholDrinks.filter { $0.date == vm.todayStr }
        let todayGrams = todayDrinks.reduce(0.0) { $0 + $1.gramsAlcohol }

        let weekDrinks = vm.data.alcoholDrinks.filter { $0.date >= vm.weekAgoStr }
        let weeklyGrams = weekDrinks.reduce(0.0) { $0 + $1.gramsAlcohol }
        let dailyAvg7d = weekDrinks.isEmpty ? 0 : weeklyGrams / 7.0

        let riskColor = vm.cachedAlcoholRisk.color

        HealthSummaryTile(
            icon: "wineglass.fill",
            iconColor: riskColor,
            label: "Alcohol",
            accessibilityLabel: "Alcohol: \(String(format: "%.0f grams today", todayGrams)), \(vm.cachedAlcoholRisk.rawValue) risk",
            accessibilityHint: "Opens habits tracking",
            action: { navigateToHabitTab(.alcohol) },
            header: {
                Text(vm.cachedAlcoholRisk.rawValue.capitalized)
                    .font(.system(size: 10)).fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(riskColor.opacity(0.2))
                    .foregroundColor(riskColor)
                    .cornerRadius(4)
            }
        ) {
            Text(String(format: "%.0fg today", todayGrams))
                .font(.headline).monospacedDigit()
                .foregroundColor(.textPrimary)
            Text(String(format: "%.0fg/d avg (7d)", dailyAvg7d))
                .font(.caption).monospacedDigit()
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Body Tile

    @ViewBuilder
    private var bodyTile: some View {
        let bmi = vm.data.profile.lifestyle.bmi

        HealthSummaryTile(
            icon: "figure.stand",
            iconColor: .blue,
            label: "Body",
            accessibilityLabel: "Body: \(bmi.map { String(format: "BMI %.1f", $0) } ?? "no BMI data")",
            accessibilityHint: "Opens body composition",
            action: { navigateTo(.body) }
        ) {
            if let bmi {
                Text(String(format: "BMI %.1f", bmi))
                    .font(.headline).monospacedDigit()
                    .foregroundColor(.textPrimary)
            } else {
                Text("--")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
            }
            Text(vm.data.eyeExams.isEmpty ? "No exams" : "\(vm.data.eyeExams.count) eye exam\(vm.data.eyeExams.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Blood Tile

    @ViewBuilder
    private var bloodTile: some View {
        let tests = vm.data.bloodTests
        let latestDate = vm.sortedBloodTests.first?.date

        HealthSummaryTile(
            icon: "drop.fill",
            iconColor: .accentColor,
            label: "Blood",
            accessibilityLabel: "Blood: \(tests.count) test\(tests.count == 1 ? "" : "s")",
            accessibilityHint: "Opens blood test tracking",
            action: { navigateTo(.blood) }
        ) {
            Text("\(tests.count) test\(tests.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text(latestDate ?? "No tests")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Epigenetic Tile

    @ViewBuilder
    private var epigeneticTile: some View {
        let latest = vm.sortedEpigeneticTests.first

        HealthSummaryTile(
            icon: "dna",
            iconColor: .purple,
            label: "Epigenetic",
            accessibilityLabel: "Epigenetic age: \(latest.map { String(format: "biological %.1f years, chronological %.1f years", $0.biologicalAge, $0.chronologicalAge) } ?? "no tests")",
            accessibilityHint: "Opens genome and epigenetic tracking",
            action: { navigateTo(.genome) }
        ) {
            if let t = latest {
                Text(String(format: "Bio %.1f yr", t.biologicalAge))
                    .font(.headline).monospacedDigit()
                    .foregroundColor(.textPrimary)
                if let pace = t.paceOfAging {
                    Text(String(format: "Pace: %.2f", pace))
                        .font(.caption).monospacedDigit()
                        .foregroundColor(pace < 1 ? .success : .warning)
                }
                Text(String(format: "Chrono %.1f yr", t.chronologicalAge))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            } else {
                Text("--")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("No tests")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .proGated()
    }

    // MARK: - Eyes Tile

    @ViewBuilder
    private var eyesTile: some View {
        let exams = vm.data.eyeExams
        let latestDate = vm.sortedEyeExams.first?.date

        HealthSummaryTile(
            icon: "eye.fill",
            iconColor: .teal,
            label: "Eyes",
            accessibilityLabel: "Eyes: \(exams.count) exam\(exams.count == 1 ? "" : "s")",
            accessibilityHint: "Opens body and eye tracking",
            action: { navigateTo(.body) }
        ) {
            Text("\(exams.count) exam\(exams.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text(latestDate ?? "No exams")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Lifestyle Tile

    @ViewBuilder
    private var lifestyleTile: some View {
        let lifestyle = vm.data.profile.lifestyle
        let isConfigured = lifestyle != .default

        HealthSummaryTile(
            icon: "list.bullet.clipboard",
            iconColor: .green,
            label: "Lifestyle",
            accessibilityLabel: "Lifestyle: \(isConfigured ? "questionnaire complete" : "not configured")",
            accessibilityHint: "Opens lifestyle questionnaire",
            action: { navigateTo(.lifestyle) }
        ) {
            Text(isConfigured ? "Active" : "Not Set")
                .font(.headline)
                .foregroundColor(isConfigured ? .success : .textMuted)
            Text(isConfigured ? "Questionnaire complete" : "Tap to configure")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Recommendations Card

    @ViewBuilder
    private var recommendationsCard: some View {
        let actionable = vm.cachedRecommendations.filter { $0.yearsGained > 0 }
        let dataGaps = vm.cachedRecommendations.filter { $0.yearsGained == 0 }
        let totalGainable = actionable.reduce(0.0) { $0 + $1.yearsGained }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.title3)
                Text("Recommendations")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                if totalGainable > 0 {
                    Text(String(format: "+%.1f yr possible", totalGainable))
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.success.opacity(0.2))
                        .foregroundColor(.success)
                        .cornerRadius(6)
                }
            }

            if !actionable.isEmpty {
                Text("Changes that could extend your life")
                    .font(.caption)
                    .foregroundColor(.textMuted)

                ForEach(actionable) { rec in
                    recommendationRow(rec)
                }
            }

            if !dataGaps.isEmpty {
                if !actionable.isEmpty {
                    Divider().background(Color.cardBorder)
                }

                Text("Track more for better estimates")
                    .font(.caption)
                    .foregroundColor(.textMuted)

                ForEach(dataGaps) { rec in
                    dataGapRow(rec)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private func recommendationRow(_ rec: RecommendationEngine.Recommendation) -> some View {
        HStack(spacing: 12) {
            Button { openRecommendation(rec, fallback: .lifestyle) } label: {
                HStack(spacing: 12) {
                    Image(systemName: rec.icon)
                        .foregroundColor(.success)
                        .font(.body)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(rec.title)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.textPrimary)
                            CitationBadge(
                                ids: rec.citationIds,
                                claim: "Source for: \(rec.title)"
                            )
                        }
                        Text(rec.detail)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(String(format: "+%.1f yr", rec.yearsGained))
                        .font(.subheadline).fontWeight(.bold).monospacedDigit()
                        .foregroundColor(.success)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rec.title): \(rec.detail). Could gain \(String(format: "%.1f", rec.yearsGained)) years.")
        .accessibilityHint("Tap to open related section")
    }

    @ViewBuilder
    private func dataGapRow(_ rec: RecommendationEngine.Recommendation) -> some View {
        HStack(spacing: 12) {
            Button { openRecommendation(rec, fallback: .overview) } label: {
                HStack(spacing: 12) {
                    Image(systemName: rec.icon)
                        .foregroundColor(.textMuted)
                        .font(.body)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(rec.title)
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.textSecondary)
                            CitationBadge(
                                ids: rec.citationIds,
                                claim: "Source for: \(rec.title)"
                            )
                        }
                        Text(rec.detail)
                            .font(.caption)
                            .foregroundColor(.textMuted)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.textMuted)
                        .font(.caption)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rec.title): \(rec.detail)")
        .accessibilityHint("Tap to open related section")
    }

    // MARK: - Helpers

    private func navigateTo(_ page: AppPage) {
        selectedTab = page.rawValue
    }

    private func navigateToHabitTab(_ tab: HabitTab) {
        habitsTab = tab
        selectedTab = AppPage.habits.rawValue
    }

    private func openRecommendation(_ rec: RecommendationEngine.Recommendation, fallback: AppPage) {
        let target = AppPage(rawValue: rec.targetPage) ?? fallback
        if target == .habits, let tab = rec.targetHabitTab {
            navigateToHabitTab(tab)
            return
        }
        navigateTo(target)
    }

}
