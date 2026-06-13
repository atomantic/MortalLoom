import SwiftUI
import Charts

// MARK: - Sleep Data Point

private struct SleepPoint: Identifiable {
    let id = UUID()
    let date: Date
    let hours: Double
}

private struct SleepStagePoint: Identifiable {
    let id = UUID()
    let date: Date
    let stage: String
    let hours: Double
}

// MARK: - SleepView

struct SleepView: View {
    @State private var sleepPoints: [SleepPoint] = []
    @State private var stagePoints: [SleepStagePoint] = []
    @State private var summary: SleepEngine.SleepSummary?
    @State private var daylightConsistencyPoints: [SleepEngine.DaylightConsistencyPoint] = []
    @State private var daylightConsistencyR: Double?
    @State private var userAge: Int = 0
    @State private var isLoading = true
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if sleepPoints.isEmpty {
                    emptySleepCard
                } else if let summary {
                    if isWide { wideSleepContent(summary) } else { narrowSleepContent(summary) }
                }
            }
            .padding()
            .readContainerWidth { containerWidth = $0 }
        }
        .background(Color.bg)
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
    }

    @ViewBuilder
    private func narrowSleepContent(_ summary: SleepEngine.SleepSummary) -> some View {
        sleepScoreCard(summary)
        sleepDurationChart
        if let stages = summary.stageBreakdown, stages.totalNights > 0 {
            sleepStageCard(stages)
            sleepStageChart
        }
        if let apnea = summary.apneaRisk {
            breathingCard(apnea: apnea, avgBD: summary.avgBreathingDisturbances)
        }
        sleepStatsCard(summary)
        if !daylightConsistencyPoints.isEmpty {
            daylightConsistencyCard
        }
        longevityImpactCard(summary)
    }

    @ViewBuilder
    private func wideSleepContent(_ summary: SleepEngine.SleepSummary) -> some View {
        sleepScoreCard(summary)
        if let stages = summary.stageBreakdown, stages.totalNights > 0 {
            HStack(alignment: .top, spacing: 16) {
                sleepDurationChart
                sleepStageChart
            }
            if let apnea = summary.apneaRisk {
                HStack(alignment: .top, spacing: 16) {
                    sleepStageCard(stages)
                    breathingCard(apnea: apnea, avgBD: summary.avgBreathingDisturbances)
                }
            } else {
                sleepStageCard(stages)
            }
        } else {
            sleepDurationChart
            if let apnea = summary.apneaRisk {
                breathingCard(apnea: apnea, avgBD: summary.avgBreathingDisturbances)
            }
        }
        HStack(alignment: .top, spacing: 16) {
            sleepStatsCard(summary)
            longevityImpactCard(summary)
        }
        if !daylightConsistencyPoints.isEmpty {
            daylightConsistencyCard
        }
    }

    // MARK: - Empty State

    private var emptySleepCard: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                icon: "bed.double",
                title: "No sleep data available",
                subtitle: "Sleep data is synced from Apple Health. Wear your Apple Watch or use a sleep tracking app to record sleep."
            )
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Sleep Score Card

    private func sleepScoreCard(_ summary: SleepEngine.SleepSummary) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: summary.rating.systemImage)
                    .font(.title2)
                    .foregroundColor(summary.rating.color.semanticColor)
                Text("Sleep Overview")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(summary.rating.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(summary.rating.color.semanticColor)
            }

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1fh", summary.averageDuration))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("avg / night")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
                // Hero is a fixed 32pt; cap the caption's Dynamic Type growth so
                // this stat column stays legible alongside it beyond AX3.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Divider().frame(height: 48)

                VStack(alignment: .leading, spacing: 8) {
                    if let avg7 = summary.avg7Day {
                        HStack(spacing: 4) {
                            Text("7-day:")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                            Text(String(format: "%.1fh", avg7))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)
                        }
                    }
                    if let avg30 = summary.avg30Day {
                        HStack(spacing: 4) {
                            Text("30-day:")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                            Text(String(format: "%.1fh", avg30))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("Nights:")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                        Text("\(summary.totalNights)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep overview: \(String(format: "%.1f", summary.averageDuration)) hours average, rated \(summary.rating.rawValue)")
    }

    // MARK: - Sleep Duration Chart

    private var sleepDurationChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Duration")
                .font(.headline)
                .foregroundColor(.textPrimary)

            Chart(sleepPoints) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Hours", point.hours)
                )
                .foregroundStyle(barColor(for: point.hours))
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(values: .stride(by: 2)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))h")
                        }
                    }
                }
            }
            .chartYScale(domain: 0...12)
            .frame(height: Layout.chartFrameHeight)

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .success, label: "7-9h (optimal)")
                legendItem(color: .accentColor, label: "6-7h / 9-10h")
                legendItem(color: .danger, label: "<6h / >10h")
            }
            .font(.caption2)
        }
        .padding()
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep duration chart showing \(sleepPoints.count) nights, optimal range 7 to 9 hours")
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundColor(.textMuted)
        }
    }

    private func barColor(for hours: Double) -> Color {
        if hours >= 7 && hours <= 9 { return .success }
        if hours >= 6 && hours <= 10 { return .accentColor }
        return .danger
    }

    // MARK: - Sleep Stage Breakdown Card

    private func sleepStageCard(_ stages: SleepEngine.SleepStageBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stages")
                .font(.headline)
                .foregroundColor(.textPrimary)

            HStack(spacing: 16) {
                stageMetric(
                    label: "Deep",
                    hours: stages.avgDeepHours,
                    pct: stages.deepPct,
                    quality: stages.deepQuality,
                    icon: "moon.zzz.fill"
                )
                stageMetric(
                    label: "REM",
                    hours: stages.avgRemHours,
                    pct: stages.remPct,
                    quality: stages.remQuality,
                    icon: "brain.head.profile"
                )
                stageMetric(
                    label: "Core",
                    hours: stages.avgCoreHours,
                    pct: stages.corePct,
                    quality: nil,
                    icon: "moon.fill"
                )
            }

            Text("Deep sleep supports cognitive health and waste clearance. REM supports emotional regulation and cardiovascular health.")
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
        .padding()
        .cardStyle()
    }

    private func stageMetric(label: String, hours: Double, pct: Double, quality: SleepEngine.StageQuality?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(quality.map { $0.color.semanticColor } ?? .textMuted)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            Text(String(format: "%.1fh", hours))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text(String(format: "%.0f%%", pct))
                .font(.caption2)
                .foregroundColor(.textSecondary)
            if let quality {
                Text(quality.rawValue)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(quality.color.semanticColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) sleep: \(String(format: "%.1f", hours)) hours, \(String(format: "%.0f", pct)) percent")
    }

    // MARK: - Sleep Stage Stacked Chart

    private var sleepStageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stage Breakdown")
                .font(.headline)
                .foregroundColor(.textPrimary)

            Chart(stagePoints) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Hours", point.hours)
                )
                .foregroundStyle(by: .value("Stage", point.stage))
                .cornerRadius(2)
            }
            .chartForegroundStyleScale([
                "Deep": Color.indigo,
                "REM": Color.cyan,
                "Core": Color.accentColor,
            ])
            .chartYAxis {
                AxisMarks(values: .stride(by: 2)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))h")
                        }
                    }
                }
            }
            .chartYScale(domain: 0...12)
            .frame(height: Layout.chartFrameHeight)

            HStack(spacing: 16) {
                legendItem(color: .indigo, label: "Deep")
                legendItem(color: .cyan, label: "REM")
                legendItem(color: .accentColor, label: "Core")
            }
            .font(.caption2)
        }
        .padding()
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stage breakdown chart showing deep, REM, and core sleep stacked by night over \(stagePoints.count > 0 ? "\(Set(stagePoints.map(\.date)).count)" : "0") nights")
    }

    // MARK: - Breathing Disturbances Card

    private func breathingCard(apnea: SleepEngine.ApneaRisk, avgBD: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: apnea.systemImage)
                    .font(.title2)
                    .foregroundColor(apnea.color.semanticColor)
                Text("Breathing During Sleep")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(apnea.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(apnea.color.semanticColor)
            }

            if let avgBD {
                HStack(spacing: 6) {
                    Text(String(format: "%.1f", avgBD))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("disturbances/hr avg")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
                // Hero is a fixed 28pt; cap the caption's Dynamic Type growth so
                // the row stays on one line beyond AX3.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }

            HStack(alignment: .top, spacing: 4) {
                Text("AHI thresholds: <5 normal, 5-15 mild, 15-30 moderate, >30 severe. Untreated moderate-to-severe apnea increases cardiovascular mortality 2-3x. (AASM Clinical Guidelines)")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
                CitationBadge(
                    ids: [CitationLibrary.youngApnea2008.id],
                    claim: "AHI classification and apnea mortality risk"
                )
            }
        }
        .padding()
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Breathing during sleep: \(apnea.rawValue) risk, \(avgBD.map { String(format: "%.1f", $0) } ?? "unknown") disturbances per hour")
    }

    // MARK: - Sleep Stats Card

    private func sleepStatsCard(_ summary: SleepEngine.SleepSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stats")
                .font(.headline)
                .foregroundColor(.textPrimary)

            HStack(spacing: 16) {
                statCard(
                    label: "Consistency",
                    value: String(format: "%.0f%%", summary.consistency),
                    detail: consistencyLabel(summary.consistency),
                    color: consistencyColor(summary.consistency)
                )
                statCard(
                    label: "Sleep Debt",
                    value: formatDebt(summary.debt),
                    detail: summary.debt < 0 ? "below target" : "above target",
                    color: summary.debt < -5 ? .danger : summary.debt < 0 ? .warning : .success
                )
            }
        }
        .padding()
        .cardStyle()
    }

    private func statCard(label: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.textMuted)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value), \(detail)")
    }

    private func consistencyLabel(_ score: Double) -> String {
        if score >= 80 { return "Very consistent" }
        if score >= 60 { return "Fairly consistent" }
        if score >= 40 { return "Somewhat irregular" }
        return "Irregular"
    }

    private func consistencyColor(_ score: Double) -> Color {
        if score >= 80 { return .success }
        if score >= 60 { return .accentColor }
        if score >= 40 { return .warning }
        return .danger
    }

    private func formatDebt(_ debt: Double) -> String {
        let abs = abs(debt)
        if abs < 1 { return String(format: "%.1fh", debt) }
        return String(format: "%.0fh", debt)
    }

    // MARK: - Longevity Impact Card

    private func longevityImpactCard(_ summary: SleepEngine.SleepSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Longevity Impact")
                .font(.headline)
                .foregroundColor(.textPrimary)

            HStack(spacing: 6) {
                Image(systemName: summary.longevityYears >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(summary.longevityYears >= 0 ? .success : .danger)
                    .font(.caption)
                Text("Average sleep of \(String(format: "%.1f", summary.averageDuration))h/night: \(summary.longevityYears >= 0 ? "+" : "")\(String(format: "%.1f", summary.longevityYears)) years estimated life expectancy impact")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            CitationSourceRow(
                label: "Source: Cappuccio et al., Sleep 2010 — meta-analysis of 1.3M participants",
                ids: [
                    CitationLibrary.cappuccioSleep2010.id,
                    CitationLibrary.nsfSleepDuration.id,
                ],
                claim: "Sleep duration ↔ all-cause mortality relationship"
            )
        }
        .padding()
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Longevity impact: \(summary.longevityYears >= 0 ? "plus" : "minus") \(String(format: "%.1f", abs(summary.longevityYears))) years on life expectancy from sleep habits")
    }

    // MARK: - Daylight → Consistency Correlation Card

    private var daylightConsistencyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daylight ↔ Sleep Consistency")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                if let r = daylightConsistencyR {
                    Text("r = \(String(format: "%+.2f", r))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(correlationColor(r))
                        .monospacedDigit()
                }
            }

            Chart(daylightConsistencyPoints, id: \.endDate) { point in
                PointMark(
                    x: .value("Daylight (min/day, 7-night avg)", point.avgDaylightMinutes),
                    y: .value("Sleep consistency (0–100)", point.consistency)
                )
                .foregroundStyle(Color.accentColor.opacity(0.75))
                .symbolSize(56)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))m")
                        }
                    }
                }
            }
            .chartYAxis {
                // Double literals so they match the Y axis's plottable type
                // (the chart's y-value is consistency: Double). Using Int
                // literals here would make value.as(Double.self) return nil
                // and labels would silently disappear.
                AxisMarks(values: [0.0, 25.0, 50.0, 75.0, 100.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))")
                        }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: Layout.chartFrameHeight)

            Text(daylightConsistencyExplanation)
                .font(.caption)
                .foregroundColor(.textSecondary)

            Text("Each dot = one 7-night window of overlapping data. X-axis is your average outdoor light exposure on the days leading into those nights; Y-axis is how consistent your sleep durations were (100 = identical every night).")
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
        .padding()
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(daylightConsistencyAccessibilityLabel)
    }

    private var daylightConsistencyExplanation: String {
        guard let r = daylightConsistencyR else {
            // SleepEngine returns nil from two distinct cases: too few points (<3)
            // OR zero variance in either series. Distinguish them in the copy.
            if daylightConsistencyPoints.count < 3 {
                return "Need more overlapping daylight and sleep data to estimate a correlation."
            }
            return "Not enough variation in your daylight or sleep data to compute a correlation."
        }
        switch SleepEngine.classifyCorrelation(r) {
        case .strongPositive:
            return "Strong positive: 7-night windows with more prior-day outdoor light tend to have more consistent sleep."
        case .weakPositive:
            return "Weak positive: more prior-day daylight in a window tracks somewhat with more consistent sleep."
        case .none:
            return "No clear relationship in your data yet."
        case .weakNegative:
            return "Weak negative: more prior-day daylight in a window tracks somewhat with less consistent sleep — unusual; check other factors."
        case .strongNegative:
            return "Strong negative: more prior-day daylight in a window tracks with less consistent sleep — unusual; check other factors."
        }
    }

    private func correlationColor(_ r: Double) -> Color {
        switch SleepEngine.classifyCorrelation(r) {
        case .strongPositive: return .success
        case .weakPositive: return .accentColor
        case .none: return .textMuted
        case .weakNegative, .strongNegative: return .warning
        }
    }

    private var daylightConsistencyAccessibilityLabel: String {
        let base = "Daylight and sleep consistency scatter chart over \(daylightConsistencyPoints.count) sliding seven-night windows."
        guard let r = daylightConsistencyR else { return base + " Not enough data for a correlation." }
        return base + " Pearson correlation \(String(format: "%.2f", r))."
    }

    // MARK: - Data Loading

    private func loadData() async {
        let data = await DataStore.shared.getData()

        if let birthStr = data.profile.birthDate,
           let birthDate = DateFormatting.dateFromString(birthStr) {
            userAge = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        }

        // Extract sleep hours from health metrics, sorted by date
        let metrics = data.healthMetrics
            .filter { $0.sleepHours != nil }
            .sorted { $0.date < $1.date }

        var points: [SleepPoint] = []
        var hours: [Double] = []
        var stages: [SleepStagePoint] = []

        for metric in metrics {
            guard let sleep = metric.sleepHours,
                  let date = DateFormatting.dateFromString(metric.date) else { continue }
            points.append(SleepPoint(date: date, hours: sleep))
            hours.append(sleep)

            // Build stacked stage chart data
            if let deep = metric.sleepDeepHours {
                stages.append(SleepStagePoint(date: date, stage: "Deep", hours: deep))
            }
            if let rem = metric.sleepRemHours {
                stages.append(SleepStagePoint(date: date, stage: "REM", hours: rem))
            }
            if let core = metric.sleepCoreHours {
                stages.append(SleepStagePoint(date: date, stage: "Core", hours: core))
            }
        }

        sleepPoints = points
        stagePoints = stages
        if !hours.isEmpty {
            summary = SleepEngine.summarize(sleepHours: hours, age: userAge, metrics: metrics)
        }

        // Pass the FULL metrics list — the engine looks up daylight on the
        // prior calendar day (D-1) for each sleep night (D), so it needs
        // daylight-only days too (those have sleepHours == nil but still
        // carry the relevant prior-day signal for the next night).
        let dcPoints = SleepEngine.daylightConsistencyCorrelation(metrics: data.healthMetrics, windowNights: 7)
        daylightConsistencyPoints = dcPoints
        daylightConsistencyR = SleepEngine.daylightConsistencyCorrelationCoefficient(dcPoints)

        isLoading = false
    }
}
