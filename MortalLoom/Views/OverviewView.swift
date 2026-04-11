import SwiftUI
import Charts

struct OverviewView: View {
    @Binding var selectedTab: Int
    @State private var data: AppData = .empty
    @State private var deathClock: DeathClockEngine.DeathClockResult?
    @State private var levDeathClock: DeathClockEngine.DeathClockResult?
    @State private var lev: DeathClockEngine.LEVResult?
    @State private var countdownMode: CountdownMode = .standard
    @State private var isVisible = false
    @State private var todayStr: String = DateFormatting.todayString()
    @State private var weekAgoStr: String = DateFormatting.dateString(daysAgo: 7)
    // Pre-sorted arrays to avoid sorting in render path
    @State private var sortedBloodTests: [BloodTest] = []
    @State private var sortedEpigeneticTests: [EpigeneticTest] = []
    @State private var sortedEyeExams: [EyeExam] = []
    // Cached chart data — recomputed in recalculate(), not on every render
    @State private var cachedAlcoholRisk: AlcoholRisk = .low
    @State private var cachedHealthScore: Double = 0
    @State private var cachedNormalPoints: [TrajectoryPoint] = []
    @State private var cachedLevPoints: [TrajectoryPoint] = []
    @State private var cachedRecommendations: [RecommendationEngine.Recommendation] = []
    @State private var cachedSleepImpact: Double = 0
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    @State private var showCitations = false
    @State private var showAddGoal = false
    @State private var editingGoal: Goal?
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }

    private var apexGoal: Goal? { data.goals.activeApex }
    private var activeGoalCount: Int { data.goals.activeCount }

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
            GoalEditSheet(goal: nil, allGoals: data.goals) { newGoal in
                Task {
                    await DataStore.shared.addGoal(newGoal)
                    await loadData()
                }
            }
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditSheet(goal: goal, allGoals: data.goals, onSave: { updated in
                Task {
                    await DataStore.shared.updateGoal(updated)
                    await loadData()
                }
            }, onDelete: {
                Task {
                    await DataStore.shared.removeGoal(id: goal.id)
                    await loadData()
                }
            })
        }
    }

    @ViewBuilder
    private var narrowContentStack: some View {
        VStack(spacing: 16) {
            goalPromptCard
            if let lev { levCard(lev) }
            deathClockCard
            if deathClock != nil { lifeExpectancyFactorsCard }
            if let dc = deathClock { lifetimeHealthChart(dc) }
            vitalStatsRow
            healthGrid
            if !cachedRecommendations.isEmpty { recommendationsCard }
        }
    }

    @ViewBuilder
    private var wideContentStack: some View {
        VStack(spacing: 16) {
            goalPromptCard
            if let lev { levCard(lev) }
            HStack(alignment: .top, spacing: 16) {
                deathClockCard
                if deathClock != nil {
                    lifeExpectancyFactorsCard
                }
            }
            vitalStatsRow
            if let dc = deathClock {
                lifetimeHealthChart(dc)
                    .frame(maxWidth: .infinity)
            }
            healthGrid
            if !cachedRecommendations.isEmpty { recommendationsCard }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        let loaded = await DataStore.shared.getData()
        data = loaded
        sortedBloodTests = loaded.bloodTests.sorted(by: { $0.date > $1.date })
        sortedEpigeneticTests = loaded.epigeneticTests.sorted(by: { $0.date > $1.date })
        sortedEyeExams = loaded.eyeExams.sorted(by: { $0.date > $1.date })
        recalculate()
    }

    private func recalculate() {
        todayStr = DateFormatting.todayString()
        weekAgoStr = DateFormatting.dateString(daysAgo: 7)

        guard let birthDate = data.profile.birthDate else {
            deathClock = nil
            levDeathClock = nil
            lev = nil
            return
        }
        countdownMode = data.profile.countdownMode
        let sleepStages = SleepEngine.stageBreakdown(metrics: data.healthMetrics)
        deathClock = DeathClockEngine.calculate(
            birthDateStr: birthDate,
            sex: data.profile.biologicalSex,
            lifestyle: data.profile.lifestyle,
            genome: data.genomeScanRecord,
            sleepStages: sleepStages,
            locationProfile: data.profile.locationProfile,
            healthMetrics: data.healthMetrics
        )
        cachedSleepImpact = SleepEngine.enhancedLongevityImpact(
            averageHours: data.profile.lifestyle.sleepHoursPerNight,
            stageBreakdown: sleepStages
        )
        cachedAlcoholRisk = DeathClockEngine.alcoholRisk(drinks: data.alcoholDrinks, sex: data.profile.biologicalSex)
        cachedRecommendations = RecommendationEngine.generate(
            lifestyle: data.profile.lifestyle,
            alcoholRisk: cachedAlcoholRisk,
            hasGenomeData: data.genomeScanRecord != nil,
            hasEpigeneticData: !data.epigeneticTests.isEmpty,
            hasBloodTests: !data.bloodTests.isEmpty
        )
        if let dc = deathClock {
            levDeathClock = DeathClockEngine.calculateLEVResult(standardResult: dc, birthDateStr: birthDate, levTargetAge: data.profile.levTargetAge)
            lev = DeathClockEngine.calculateLEV(
                birthDateStr: birthDate,
                lifeExpectancy: dc.lifeExpectancy.total
            )
            recomputeChartData(dc)
        }
    }

    private func recomputeChartData(_ dc: DeathClockEngine.DeathClockResult) {
        let currentYear = Calendar.current.component(.year, from: Date())
        let birthYear = currentYear - dc.ageYears
        let deathYear = birthYear + Int(dc.lifeExpectancy.total)
        let levYear = 2045
        let levDeathYear = birthYear + 120

        cachedHealthScore = DeathClockEngine.healthScore(
            lifestyle: data.profile.lifestyle,
            ageYears: dc.ageYears,
            latestEpigeneticTest: sortedEpigeneticTests.first,
            alcoholRisk: cachedAlcoholRisk,
            healthMetrics: data.healthMetrics
        )

        cachedNormalPoints = normalTrajectory(currentYear: currentYear, deathYear: deathYear, currentHealth: cachedHealthScore)
        cachedLevPoints = levTrajectory(currentYear: currentYear, levYear: levYear, levDeathYear: levDeathYear, currentHealth: cachedHealthScore, normalPoints: cachedNormalPoints)
    }

    // MARK: - Goal Prompt Card

    @ViewBuilder
    private var goalPromptCard: some View {
        if let apex = apexGoal {
            apexGoalCard(apex)
        } else {
            setGoalCard
        }
    }

    @ViewBuilder
    private func apexGoalCard(_ goal: Goal) -> some View {
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
                if let target = goal.targetDate,
                   let targetDate = DateFormatting.dateFromString(target) {
                    Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
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

            // Progress
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Progress")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", goal.progressPercent))
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
                            .frame(width: geo.size.width * min(1, goal.progressPercent / 100), height: 8)
                    }
                }
                .frame(height: 8)
            }

            let milestoneCount = goal.milestones.count
            let checkInCount = goal.checkIns.count
            HStack(spacing: 12) {
                statPill(icon: "flag.fill", value: "\(milestoneCount)", label: "milestones")
                statPill(icon: "checkmark.circle.fill", value: "\(checkInCount)", label: "check-ins")
                statPill(icon: "circle.grid.2x2.fill", value: "\(activeGoalCount)", label: "goals")
            }

            if milestoneCount == 0 || goal.notes.isEmpty {
                goalCTAButton(
                    icon: "pencil.and.outline",
                    text: "Flesh out your goal — add milestones and plan",
                    background: AnyShapeStyle(LinearGradient.proBrandSubtleDiagonal)
                ) { editingGoal = goal }
            } else {
                goalCTAButton(
                    icon: "calendar.badge.plus",
                    text: "Schedule next work block",
                    background: AnyShapeStyle(Color.accentColor.opacity(0.15))
                ) { editingGoal = goal }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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

            Text("Examples: Write a novel, run a marathon, launch a business, learn a language fluently.")
                .font(.caption)
                .foregroundColor(.textMuted)

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

    private var activeDC: DeathClockEngine.DeathClockResult? {
        if countdownMode == .lev, let levDC = levDeathClock { return levDC }
        return deathClock
    }

    @ViewBuilder
    private var deathClockCard: some View {
        VStack(spacing: 16) {
            if let dc = activeDC {
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
                    Text(String(format: "%.0f / 100", cachedHealthScore))
                        .font(.title2).fontWeight(.bold).monospacedDigit()
                        .foregroundColor(healthScoreColor(cachedHealthScore))
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
                VStack(spacing: 8) {
                    Image(systemName: "heart.text.clipboard")
                        .font(.largeTitle)
                        .foregroundColor(.textMuted)
                    Text("Health Summary")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Configure your birth date and lifestyle in Settings to see your health summary.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
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
        let lifestyle = data.profile.lifestyle
        let metrics = data.healthMetrics
        let recoveries = metrics.compactMap(\.cardioRecovery)
        let cardioImpact = recoveries.isEmpty ? 0.0 : CardioFitnessEngine.recoveryLongevityImpact(recoveries.reduce(0, +) / Double(recoveries.count))
        let speeds = metrics.compactMap(\.walkingSpeed)
        let gaitImpact = speeds.isEmpty ? 0.0 : GaitEngine.walkingSpeedLongevityImpact(speeds.reduce(0, +) / Double(speeds.count), age: deathClock?.ageYears ?? 0)
        let bds = metrics.compactMap(\.breathingDisturbances)
        let apneaImpact = bds.isEmpty ? 0.0 : SleepEngine.apneaLongevityImpact(bds.reduce(0, +) / Double(bds.count))

        let allFactors: [(name: String, icon: String, value: Double)] = [
            ("Genome", "dna", DeathClockEngine.genomeAdjustment(data.genomeScanRecord)),
            ("Smoking", "nosign", DeathClockEngine.smokingImpact(lifestyle.smokingStatus)),
            ("Exercise", "figure.run", DeathClockEngine.exerciseImpact(lifestyle.exerciseMinutesPerWeek)),
            ("Sleep", "bed.double.fill", cachedSleepImpact),
            ("Diet", "fork.knife", DeathClockEngine.dietImpact(lifestyle.dietQuality)),
            ("Stress", "brain.head.profile", DeathClockEngine.stressImpact(lifestyle.stressLevel)),
            ("BMI", "scalemass.fill", DeathClockEngine.bmiImpact(lifestyle.bmi)),
            ("Location", "globe", deathClock?.lifeExpectancy.locationAdjustment ?? 0),
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

    private enum TrajectorySeries: String { case normal = "Expected", lev = "LEV" }

    private struct TrajectoryPoint: Identifiable {
        let year: Int
        let health: Double
        let series: TrajectorySeries
        let id: Int // precomputed for efficiency
    }

    @State private var selectedChartYear: Int?

    @ViewBuilder
    private func lifetimeHealthChart(_ dc: DeathClockEngine.DeathClockResult) -> some View {
        let currentYear = Calendar.current.component(.year, from: Date())
        let birthYear = currentYear - dc.ageYears
        let deathYear = birthYear + Int(dc.lifeExpectancy.total)
        let levYear = 2045
        let levDeathYear = birthYear + 120

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
                Text(String(format: "%.0f%%", cachedHealthScore))
                    .font(.headline).fontWeight(.bold).monospacedDigit()
                    .foregroundColor(healthScoreColor(cachedHealthScore))
            }

            ZStack(alignment: .topLeading) {
            Chart {
                // Normal expected trajectory (now → life expectancy)
                ForEach(cachedNormalPoints) { pt in
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
                ForEach(cachedLevPoints) { pt in
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
                    y: .value("Health", cachedHealthScore)
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
                let normal = cachedNormalPoints.first(where: { $0.year == yr })?.health
                let lev = cachedLevPoints.first(where: { $0.year == yr })?.health
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
        .accessibilityLabel("Health trajectory chart. Current health score \(String(format: "%.0f", cachedHealthScore)) percent. Shows expected decline and LEV optimistic path from \(currentYear) to \(levDeathYear)")
    }

    private func healthScoreColor(_ score: Double) -> Color {
        if score >= 75 { return .success }
        if score >= 50 { return .warning }
        return .danger
    }

    /// Now → LE: flat/improving for ~10 years, gentle decline mid-life, steeper only in final 5 years
    private func normalTrajectory(currentYear: Int, deathYear: Int, currentHealth: Double) -> [TrajectoryPoint] {
        var points: [TrajectoryPoint] = []
        // Three phases: improvement (10yr), slow decline, steep final (5yr)
        let improvementEndYear = currentYear + 10
        let steepDeclineYear = deathYear - 5
        let peakHealth = min(95, currentHealth + 5) // slight improvement from active health work
        // Health at start of steep decline — gradual loss over the middle years
        let atSteepStart = peakHealth * 0.55

        for year in stride(from: currentYear, through: deathYear, by: 1) {
            let health: Double
            if year <= improvementEndYear {
                // Flat to slightly improving — active health optimization
                let t = Double(year - currentYear) / Double(max(1, improvementEndYear - currentYear))
                health = currentHealth + (peakHealth - currentHealth) * t
            } else if year <= steepDeclineYear {
                // Gradual age-related decline
                let t = Double(year - improvementEndYear) / Double(max(1, steepDeclineYear - improvementEndYear))
                health = peakHealth + (atSteepStart - peakHealth) * t
            } else {
                // Steep final decline
                let t = Double(year - steepDeclineYear) / Double(max(1, deathYear - steepDeclineYear))
                health = atSteepStart * (1.0 - t * t)
            }
            points.append(TrajectoryPoint(year: year, health: max(0, health), series: .normal, id: year))
        }
        return points
    }

    /// Same as normal until LEV year, then therapies maintain/improve health far longer
    private func levTrajectory(currentYear: Int, levYear: Int, levDeathYear: Int, currentHealth: Double, normalPoints: [TrajectoryPoint]) -> [TrajectoryPoint] {
        var points: [TrajectoryPoint] = []
        // Find health at LEV year from normal trajectory
        let healthAtLEV = normalPoints.first(where: { $0.year == levYear })?.health ?? currentHealth
        let peakHealth = min(98, healthAtLEV + 8) // LEV therapies recover + improve
        let declineStart = levDeathYear - 10

        for year in stride(from: levYear, through: levDeathYear, by: 1) {
            let health: Double
            let yearsAfterLEV = Double(year - levYear)
            let rampUpYears = 10.0 // takes ~10 years for full LEV therapies to kick in
            if yearsAfterLEV <= rampUpYears {
                // Recovery and improvement as therapies take effect
                let t = yearsAfterLEV / rampUpYears
                health = healthAtLEV + (peakHealth - healthAtLEV) * t
            } else if year <= declineStart {
                // Maintained near-peak with very slow aging
                let t = Double(year - levYear - Int(rampUpYears)) / Double(max(1, declineStart - levYear - Int(rampUpYears)))
                health = peakHealth - (peakHealth * 0.08 * t)
            } else {
                // Gentle decline at end
                let t = Double(year - declineStart) / Double(max(1, levDeathYear - declineStart))
                let atDecline = peakHealth * 0.92
                health = atDecline * (1.0 - 0.6 * t * t)
            }
            points.append(TrajectoryPoint(year: year, health: max(0, health), series: .lev, id: year + 10000))
        }
        return points
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
        let dc = activeDC
        HStack(spacing: 12) {
            vitalStatCard(
                title: "Current Age",
                value: dc.map { "\($0.ageYears)" } ?? "--",
                icon: "person.fill",
                color: .blue
            )
            vitalStatCard(
                title: "Years Left",
                value: dc.map { String(format: "%.1f", $0.yearsRemaining) } ?? "--",
                icon: "hourglass",
                color: countdownMode == .lev ? .success : .accentColor
            )
            vitalStatCard(
                title: "Healthy Years",
                value: dc.map { String(format: "%.1f", $0.healthyYearsRemaining) } ?? "--",
                icon: "heart.fill",
                color: .success
            )
        }
    }

    @ViewBuilder
    private func vitalStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(value)
                .font(.title2).fontWeight(.bold).monospacedDigit()
                .foregroundColor(.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Health Summary Grid

    @ViewBuilder
    private var healthGrid: some View {
        let columns = isWide
            ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        VStack(alignment: .leading, spacing: 8) {
            Text("Health Summary")
                .font(.headline)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 4)

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
        let todayDrinks = data.alcoholDrinks.filter { $0.date == todayStr }
        let todayGrams = todayDrinks.reduce(0.0) { $0 + $1.gramsAlcohol }

        let weekDrinks = data.alcoholDrinks.filter { $0.date >= weekAgoStr }
        let weeklyGrams = weekDrinks.reduce(0.0) { $0 + $1.gramsAlcohol }
        let dailyAvg7d = weekDrinks.isEmpty ? 0 : weeklyGrams / 7.0

        let riskColor = cachedAlcoholRisk.color

        Button { navigateTo(.habits) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "wineglass.fill")
                        .foregroundColor(riskColor)
                        .font(.title3)
                    Spacer()
                    Text(cachedAlcoholRisk.rawValue.capitalized)
                        .font(.system(size: 10)).fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(riskColor.opacity(0.2))
                        .foregroundColor(riskColor)
                        .cornerRadius(4)
                }
                Text(String(format: "%.0fg today", todayGrams))
                    .font(.headline).monospacedDigit()
                    .foregroundColor(.textPrimary)
                Text(String(format: "%.0fg/d avg (7d)", dailyAvg7d))
                    .font(.caption).monospacedDigit()
                    .foregroundColor(.textSecondary)
                Text("Alcohol")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alcohol: \(String(format: "%.0f grams today", todayGrams)), \(cachedAlcoholRisk.rawValue) risk")
        .accessibilityHint("Opens habits tracking")
    }

    // MARK: - Body Tile

    @ViewBuilder
    private var bodyTile: some View {
        let bmi = data.profile.lifestyle.bmi

        Button { navigateTo(.body) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "figure.stand")
                        .foregroundColor(.blue)
                        .font(.title3)
                    Spacer()
                }
                if let bmi {
                    Text(String(format: "BMI %.1f", bmi))
                        .font(.headline).monospacedDigit()
                        .foregroundColor(.textPrimary)
                } else {
                    Text("--")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                }
                Text(data.eyeExams.isEmpty ? "No exams" : "\(data.eyeExams.count) eye exam\(data.eyeExams.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("Body")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Body: \(bmi.map { String(format: "BMI %.1f", $0) } ?? "no BMI data")")
        .accessibilityHint("Opens body composition")
    }

    // MARK: - Blood Tile

    @ViewBuilder
    private var bloodTile: some View {
        let tests = data.bloodTests
        let latestDate = sortedBloodTests.first?.date

        Button { navigateTo(.blood) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                    Spacer()
                }
                Text("\(tests.count) test\(tests.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text(latestDate ?? "No tests")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("Blood")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Blood: \(tests.count) test\(tests.count == 1 ? "" : "s")")
        .accessibilityHint("Opens blood test tracking")
    }

    // MARK: - Epigenetic Tile

    @ViewBuilder
    private var epigeneticTile: some View {
        let latest = sortedEpigeneticTests.first

        Button { navigateTo(.genome) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "dna")
                        .foregroundColor(.purple)
                        .font(.title3)
                    Spacer()
                }
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
                Text("Epigenetic")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Epigenetic age: \(latest.map { String(format: "biological %.1f years, chronological %.1f years", $0.biologicalAge, $0.chronologicalAge) } ?? "no tests")")
        .accessibilityHint("Opens genome and epigenetic tracking")
        .proGated()
    }

    // MARK: - Eyes Tile

    @ViewBuilder
    private var eyesTile: some View {
        let exams = data.eyeExams
        let latestDate = sortedEyeExams.first?.date

        Button { navigateTo(.body) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.teal)
                        .font(.title3)
                    Spacer()
                }
                Text("\(exams.count) exam\(exams.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text(latestDate ?? "No exams")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("Eyes")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Eyes: \(exams.count) exam\(exams.count == 1 ? "" : "s")")
        .accessibilityHint("Opens body and eye tracking")
    }

    // MARK: - Lifestyle Tile

    @ViewBuilder
    private var lifestyleTile: some View {
        let lifestyle = data.profile.lifestyle
        let isConfigured = lifestyle != .default

        Button { navigateTo(.lifestyle) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundColor(.green)
                        .font(.title3)
                    Spacer()
                }
                Text(isConfigured ? "Active" : "Not Set")
                    .font(.headline)
                    .foregroundColor(isConfigured ? .success : .textMuted)
                Text(isConfigured ? "Questionnaire complete" : "Tap to configure")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("Lifestyle")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lifestyle: \(isConfigured ? "questionnaire complete" : "not configured")")
        .accessibilityHint("Opens lifestyle questionnaire")
    }

    // MARK: - Recommendations Card

    @ViewBuilder
    private var recommendationsCard: some View {
        let actionable = cachedRecommendations.filter { $0.yearsGained > 0 }
        let dataGaps = cachedRecommendations.filter { $0.yearsGained == 0 }
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
        Button { navigateTo(AppPage(rawValue: rec.targetPage) ?? .lifestyle) } label: {
            HStack(spacing: 12) {
                Image(systemName: rec.icon)
                    .foregroundColor(.success)
                    .font(.body)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rec.title): \(rec.detail). Could gain \(String(format: "%.1f", rec.yearsGained)) years.")
        .accessibilityHint("Tap to open related section")
    }

    @ViewBuilder
    private func dataGapRow(_ rec: RecommendationEngine.Recommendation) -> some View {
        Button { navigateTo(AppPage(rawValue: rec.targetPage) ?? .overview) } label: {
            HStack(spacing: 12) {
                Image(systemName: rec.icon)
                    .foregroundColor(.textMuted)
                    .font(.body)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textSecondary)
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rec.title): \(rec.detail)")
        .accessibilityHint("Tap to open related section")
    }

    // MARK: - Helpers

    private func navigateTo(_ page: AppPage) {
        selectedTab = page.rawValue
    }

}
