import SwiftUI
import Charts

// MARK: - Substance Tab Enum

private enum SubstanceTab: String, CaseIterable {
    case myHabits = "My Habits"
    case alcohol = "Alcohol"
    case nicotine = "Nicotine"
    case sauna = "Sauna"
}

// MARK: - Volume Unit

private enum VolumeUnit: String, CaseIterable {
    case oz = "oz"
    case ml = "ml"

    var toOz: Double {
        switch self {
        case .oz: 1.0
        case .ml: 1.0 / 29.5735
        }
    }
}

// MARK: - Alcohol Risk Color

extension AlcoholRisk {
    var color: Color {
        switch self {
        case .low: .success
        case .moderate: .warning
        case .high: .danger
        }
    }
}

// MARK: - Date Helpers

private func todayString() -> String {
    DateFormatting.todayString()
}

private func dateString(daysAgo: Int) -> String {
    DateFormatting.dateString(daysAgo: daysAgo)
}

private func displayDate(_ dateStr: String) -> String {
    DateFormatting.displayDate(dateStr)
}

private func last30DayStrings() -> [String] {
    (0..<30).reversed().map { dateString(daysAgo: $0) }
}

// MARK: - Chart Data Point

private struct DailyAmount: Identifiable {
    let id: String
    let date: String
    let amount: Double

    init(date: String, amount: Double) {
        self.id = date
        self.date = date
        self.amount = amount
    }
}

// MARK: - SubstancesView

struct SubstancesView: View {
    @AppStorage("substances.selectedTab") private var selectedTab: SubstanceTab = .myHabits

    // Alcohol state
    @State private var alcoholDrinks: [AlcoholDrink] = []
    @State private var alcoholPresets: [AlcoholPreset] = []
    @State private var biologicalSex: BiologicalSex?

    // Nicotine state
    @State private var nicotineEntries: [NicotineEntry] = []
    @State private var nicotinePresets: [NicotinePreset] = []

    // Sauna state
    @State private var saunaSessions: [SaunaSession] = []
    @State private var saunaPresets: [SaunaPreset] = []

    // Health metrics for correlation charts
    @State private var healthMetrics: [HealthMetricEntry] = []
    private var metricsByDate: [String: HealthMetricEntry] {
        Dictionary(healthMetrics.map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    // Alcohol form
    @State private var alcoName = ""
    @State private var alcoVolume = ""
    @State private var alcoVolumeUnit: VolumeUnit = .oz
    @State private var alcoABV = ""
    @State private var alcoCount = "1"
    @State private var alcoDate = Date()

    // Nicotine form
    @State private var nicoProduct = ""
    @State private var nicoMgPerUnit = ""
    @State private var nicoCount = "1"
    @State private var nicoDate = Date()

    // Sauna form
    @State private var saunaType: SaunaType = .infrared
    @State private var saunaTemp = "140"
    @State private var saunaDuration = "25"
    @State private var saunaDate = Date()

    // Edit sheets
    @State private var editingDrink: AlcoholDrink?
    @State private var editingNicotine: NicotineEntry?
    @State private var editingSauna: SaunaSession?
    @State private var showDeleteConfirm = false
    @State private var showAlcoholPresetManager = false
    @State private var showNicotinePresetManager = false
    @State private var showSaunaPresetManager = false
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }

    @State private var toastMessage: String?

    // Edit form state
    @State private var editAlcoName = ""
    @State private var editAlcoOz = ""
    @State private var editAlcoABV = ""
    @State private var editAlcoCount = ""
    @State private var editAlcoDate = ""

    @State private var editNicoProduct = ""
    @State private var editNicoMg = ""
    @State private var editNicoCount = ""
    @State private var editNicoDate = ""

    @State private var editSaunaType: SaunaType = .infrared
    @State private var editSaunaTemp = ""
    @State private var editSaunaDuration = ""
    @State private var editSaunaDate = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Substance", selection: $selectedTab) {
                    ForEach(SubstanceTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch selectedTab {
                case .myHabits:
                    HabitsSection()
                case .alcohol:
                    alcoholSection
                case .nicotine:
                    nicotineSection
                case .sauna:
                    saunaSection
                }
            }
            .padding()
            .readContainerWidth { containerWidth = $0 }
        }
        .background(Color.bg)
        .task {
            if let arg = AppConstants.startSubstanceTab,
               let tab = SubstanceTab.allCases.first(where: { $0.rawValue.lowercased() == arg }) {
                selectedTab = tab
            }
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
        .sheet(item: $editingDrink) { drink in
            alcoholEditSheet(drink)
        }
        .sheet(item: $editingNicotine) { entry in
            nicotineEditSheet(entry)
        }
        .sheet(isPresented: $showAlcoholPresetManager) {
            AlcoholPresetManagerView(presets: $alcoholPresets, onSave: { newPresets in
                Task { await DataStore.shared.setAlcoholPresets(newPresets) }
            })
        }
        .sheet(isPresented: $showNicotinePresetManager) {
            NicotinePresetManagerView(presets: $nicotinePresets, onSave: { newPresets in
                Task { await DataStore.shared.setNicotinePresets(newPresets) }
            })
        }
        .sheet(item: $editingSauna) { session in
            saunaEditSheet(session)
        }
        .sheet(isPresented: $showSaunaPresetManager) {
            SaunaPresetManagerView(presets: $saunaPresets, onSave: { newPresets in
                Task { await DataStore.shared.setSaunaPresets(newPresets) }
            })
        }
        .toast($toastMessage)
    }

    // MARK: - Data Loading

    private func loadData() async {
        let data = await DataStore.shared.getData()
        alcoholDrinks = data.alcoholDrinks
        alcoholPresets = data.alcoholPresets
        nicotineEntries = data.nicotineEntries
        nicotinePresets = data.nicotinePresets
        biologicalSex = data.profile.biologicalSex
        healthMetrics = data.healthMetrics
        saunaSessions = data.saunaSessions
        saunaPresets = data.saunaPresets
    }

    // MARK: - Alcohol Section

    @ViewBuilder
    private var alcoholSection: some View {
        alcoholQuickAdd
        alcoholStatsBar
        if isWide {
            HStack(alignment: .top, spacing: 16) {
                alcoholChart
                alcoholHrvCorrelation
            }
        } else {
            alcoholChart
            alcoholHrvCorrelation
        }
        alcoholSleepCorrelation
        alcoholBreathingCorrelation
        alcoholCustomForm
        alcoholHistory
    }

    // MARK: Alcohol Stats

    private var alcoholStatsBar: some View {
        let today = todayString()
        let todayGrams = alcoholDrinks.filter { $0.date == today }.reduce(0.0) { $0 + $1.gramsAlcohol }
        let avg7 = SubstanceEngine.rollingAverageGrams(drinks: alcoholDrinks, days: 7)
        let avg30 = SubstanceEngine.rollingAverageGrams(drinks: alcoholDrinks, days: 30)
        let weeklyTotal = SubstanceEngine.weeklyTotalStandardDrinks(drinks: alcoholDrinks)
        let allTimeAvg = SubstanceEngine.allTimeAverageGrams(drinks: alcoholDrinks)
        let risk = SubstanceEngine.alcoholRisk(drinks: alcoholDrinks, sex: biologicalSex)
        let weeklyThreshold: Double = (biologicalSex == .female) ? 7.0 : 14.0

        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                statItem(label: "Today", value: String(format: "%.1fg", todayGrams))
                Divider().frame(height: 40)
                statItem(label: "7d Avg", value: String(format: "%.1fg", avg7))
                Divider().frame(height: 40)
                statItem(label: "30d Avg", value: String(format: "%.1fg", avg30))
            }

            HStack(spacing: 0) {
                statItem(
                    label: "Weekly",
                    value: String(format: "%.1f / %.0f std", weeklyTotal, weeklyThreshold),
                    valueColor: weeklyTotal > weeklyThreshold ? .danger : .success
                )
                Divider().frame(height: 40)
                statItem(label: "All-time Avg", value: String(format: "%.1fg", allTimeAvg))
                Divider().frame(height: 40)
                VStack(spacing: 2) {
                    Text("Risk")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                    Text(risk.rawValue.capitalized)
                        .font(.subheadline.bold())
                        .foregroundColor(risk.color)
                }
                .frame(maxWidth: .infinity)
            }

            CitationSourceRow(
                label: "Source: NIAAA low-risk drinking limits",
                ids: [
                    CitationLibrary.niaaaLimits.id,
                    CitationLibrary.gbdAlcohol2018.id,
                ],
                claim: "Women ≤1 drink/day, ≤7/week; men ≤2 drinks/day, ≤14/week."
            )
        }
        .padding()
        .cardStyle()
    }

    // MARK: Alcohol Chart

    private var alcoholChart: some View {
        let days = last30DayStrings()
        let dailyData: [DailyAmount] = days.map { day in
            let grams = alcoholDrinks.filter { $0.date == day }.reduce(0.0) { $0 + $1.gramsAlcohol }
            return DailyAmount(date: day, amount: grams)
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Daily Alcohol (30 days)")
                .font(.headline)
                .foregroundColor(.textPrimary)

            Chart(dailyData) { item in
                BarMark(
                    x: .value("Date", item.date),
                    y: .value("Grams", item.amount)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                }
            }
            .chartYAxisLabel("grams")
            .frame(height: Layout.chartFrameHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily alcohol consumption chart showing grams of alcohol over the last 30 days")
        }
        .padding()
        .cardStyle()
    }

    // MARK: Alcohol + HRV Correlation

    @ViewBuilder
    private var alcoholHrvCorrelation: some View {
        let days = last30DayStrings()
        let drinksByDate = Dictionary(grouping: alcoholDrinks.filter { $0.abv > 1.0 }, by: \.date)

        // Build correlation data
        let correlationData: [(date: String, hrv: Double?, alcoholGrams: Double)] = days.map { day in
            let metric = metricsByDate[day]
            let grams = (drinksByDate[day] ?? []).reduce(0.0) { $0 + $1.gramsAlcohol }
            return (day, metric?.hrv, grams)
        }

        // Calculate summary stats
        let drinkingDays = correlationData.filter { $0.alcoholGrams > 1 && $0.hrv != nil }
        let soberDays = correlationData.filter { $0.alcoholGrams <= 1 && $0.hrv != nil }
        let avgDrinking = drinkingDays.isEmpty ? 0 : drinkingDays.compactMap(\.hrv).reduce(0, +) / Double(drinkingDays.count)
        let avgSober = soberDays.isEmpty ? 0 : soberDays.compactMap(\.hrv).reduce(0, +) / Double(soberDays.count)
        let hasData = !drinkingDays.isEmpty && !soberDays.isEmpty

        if hasData {
            VStack(alignment: .leading, spacing: 8) {
                Text("Alcohol + HRV Correlation")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                Chart {
                    ForEach(correlationData, id: \.date) { item in
                        if item.alcoholGrams > 0 {
                            BarMark(
                                x: .value("Date", item.date),
                                y: .value("Alcohol", item.alcoholGrams)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.4))
                        }
                        if let hrv = item.hrv {
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("HRV", hrv),
                                series: .value("Metric", "HRV")
                            )
                            .foregroundStyle(Color.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            PointMark(
                                x: .value("Date", item.date),
                                y: .value("HRV", hrv)
                            )
                            .foregroundStyle(item.alcoholGrams > 1 ? Color.accentColor : Color.cyan)
                            .symbolSize(item.alcoholGrams > 1 ? 30 : 15)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartForegroundStyleScale([
                    "HRV (ms)": Color.cyan,
                    "Alcohol (g)": Color.accentColor.opacity(0.4),
                ])
                .frame(height: Layout.chartFrameHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Alcohol and HRV correlation chart over 30 days. Average HRV on drinking days: \(String(format: "%.0f", avgDrinking)) milliseconds. Sober days: \(String(format: "%.0f", avgSober)) milliseconds")

                let pctDiff = avgSober > 0 ? ((avgSober - avgDrinking) / avgSober * 100) : 0
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Drinking Days")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(String(format: "%.0fms", avgDrinking))
                            .font(.subheadline.bold())
                            .foregroundColor(.accentColor)
                    }
                    VStack(spacing: 2) {
                        Text("Sober Days")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(String(format: "%.0fms", avgSober))
                            .font(.subheadline.bold())
                            .foregroundColor(.cyan)
                    }
                    VStack(spacing: 2) {
                        Text("Difference")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(String(format: "%.1f%%", pctDiff) + (pctDiff > 0 ? " lower" : " higher"))
                            .font(.subheadline.bold())
                            .foregroundColor(pctDiff > 0 ? .danger : .success)
                    }
                }
                .frame(maxWidth: .infinity)

                Text("HRV measures autonomic nervous system recovery. Higher is better.")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .cardStyle()
        }
    }

    // MARK: Alcohol + Sleep Quality Correlation

    @ViewBuilder
    private var alcoholSleepCorrelation: some View {
        let dataPoints = CorrelationEngine.alcoholSleepCorrelation(
            drinks: alcoholDrinks,
            healthMetrics: healthMetrics
        )

        // Split into drinking (>0.5 std drinks) vs sober days
        let drinkingDays = dataPoints.filter { $0.standardDrinks > 0.5 }
        let soberDays = dataPoints.filter { $0.standardDrinks <= 0.5 }

        let avgDeepDrinking = average(drinkingDays.compactMap(\.nextNightDeepPct))
        let avgDeepSober = average(soberDays.compactMap(\.nextNightDeepPct))
        let avgRemDrinking = average(drinkingDays.compactMap(\.nextNightRemPct))
        let avgRemSober = average(soberDays.compactMap(\.nextNightRemPct))
        let avgHoursDrinking = average(drinkingDays.compactMap(\.nextNightTotalHours))
        let avgHoursSober = average(soberDays.compactMap(\.nextNightTotalHours))

        let hasData = !drinkingDays.isEmpty && !soberDays.isEmpty
            && avgDeepDrinking != nil && avgDeepSober != nil

        if hasData {
            VStack(alignment: .leading, spacing: 8) {
                Text("Alcohol + Sleep Quality")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                // Last 60 data points max for readability
                let chartData = dataPoints.suffix(60)

                Chart {
                    ForEach(Array(chartData), id: \.date) { item in
                        if item.standardDrinks > 0 {
                            BarMark(
                                x: .value("Date", item.date),
                                y: .value("Drinks", item.standardDrinks)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.3))
                        }
                        if let deep = item.nextNightDeepPct {
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("Deep %", deep),
                                series: .value("Stage", "Deep Sleep %")
                            )
                            .foregroundStyle(Color.indigo)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        if let rem = item.nextNightRemPct {
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("REM %", rem),
                                series: .value("Stage", "REM Sleep %")
                            )
                            .foregroundStyle(Color.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartForegroundStyleScale([
                    "Deep Sleep %": Color.indigo,
                    "REM Sleep %": Color.purple,
                    "Drinks": Color.accentColor.opacity(0.3),
                ])
                .frame(height: Layout.chartFrameHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Alcohol and sleep quality correlation. Deep sleep on drinking nights: \(String(format: "%.1f", avgDeepDrinking ?? 0))%. Sober nights: \(String(format: "%.1f", avgDeepSober ?? 0))%. REM on drinking nights: \(String(format: "%.1f", avgRemDrinking ?? 0))%. Sober nights: \(String(format: "%.1f", avgRemSober ?? 0))%")

                // Summary stats
                let deepDiff = pctDifference(avgDeepSober, avgDeepDrinking)
                let remDiff = pctDifference(avgRemSober, avgRemDrinking)
                let hoursDiff = pctDifference(avgHoursSober, avgHoursDrinking)

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        sleepStatColumn(
                            label: "Deep (Drinking)",
                            value: String(format: "%.1f%%", avgDeepDrinking ?? 0),
                            color: .accentColor
                        )
                        sleepStatColumn(
                            label: "Deep (Sober)",
                            value: String(format: "%.1f%%", avgDeepSober ?? 0),
                            color: .indigo
                        )
                        sleepStatColumn(
                            label: "Deep Δ",
                            value: String(format: "%.1f%%", abs(deepDiff ?? 0)) + (deepDiff.map { $0 > 0 ? " less" : " more" } ?? ""),
                            color: (deepDiff ?? 0) > 0 ? .danger : .success
                        )
                    }
                    HStack(spacing: 12) {
                        sleepStatColumn(
                            label: "REM (Drinking)",
                            value: String(format: "%.1f%%", avgRemDrinking ?? 0),
                            color: .accentColor
                        )
                        sleepStatColumn(
                            label: "REM (Sober)",
                            value: String(format: "%.1f%%", avgRemSober ?? 0),
                            color: .purple
                        )
                        sleepStatColumn(
                            label: "REM Δ",
                            value: String(format: "%.1f%%", abs(remDiff ?? 0)) + (remDiff.map { $0 > 0 ? " less" : " more" } ?? ""),
                            color: (remDiff ?? 0) > 0 ? .danger : .success
                        )
                    }
                    if let hDrk = avgHoursDrinking, let hSob = avgHoursSober {
                        HStack(spacing: 12) {
                            sleepStatColumn(
                                label: "Hours (Drinking)",
                                value: String(format: "%.1fh", hDrk),
                                color: .accentColor
                            )
                            sleepStatColumn(
                                label: "Hours (Sober)",
                                value: String(format: "%.1fh", hSob),
                                color: .cyan
                            )
                            sleepStatColumn(
                                label: "Hours Δ",
                                value: String(format: "%.1f%%", abs(hoursDiff ?? 0)) + (hoursDiff.map { $0 > 0 ? " less" : " more" } ?? ""),
                                color: (hoursDiff ?? 0) > 0 ? .danger : .success
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Text("Deep & REM sleep are critical for recovery. Alcohol suppresses both stages.")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .cardStyle()
        }
    }

    private func sleepStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.textMuted)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func pctDifference(_ baseline: Double?, _ comparison: Double?) -> Double? {
        guard let b = baseline, let c = comparison, b > 0 else { return nil }
        return (b - c) / b * 100
    }

    // MARK: Alcohol + Breathing Disturbances Correlation

    @ViewBuilder
    private var alcoholBreathingCorrelation: some View {
        let dataPoints = CorrelationEngine.alcoholBreathingCorrelation(
            drinks: alcoholDrinks,
            healthMetrics: healthMetrics
        )

        let drinkingDays = dataPoints.filter { $0.standardDrinks > 0.5 }
        let soberDays = dataPoints.filter { $0.standardDrinks <= 0.5 }

        let avgDistDrinking = average(drinkingDays.compactMap(\.nextNightDisturbances))
        let avgDistSober = average(soberDays.compactMap(\.nextNightDisturbances))

        let hasData = !drinkingDays.isEmpty && !soberDays.isEmpty
            && avgDistDrinking != nil && avgDistSober != nil

        if hasData {
            VStack(alignment: .leading, spacing: 8) {
                Text("Alcohol + Breathing Disturbances")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                let chartData = dataPoints.suffix(60)

                Chart {
                    ForEach(Array(chartData), id: \.date) { item in
                        if item.standardDrinks > 0 {
                            BarMark(
                                x: .value("Date", item.date),
                                y: .value("Drinks", item.standardDrinks)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.3))
                        }
                        if let dist = item.nextNightDisturbances {
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("Events/hr", dist),
                                series: .value("Metric", "Disturbances")
                            )
                            .foregroundStyle(Color.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            PointMark(
                                x: .value("Date", item.date),
                                y: .value("Events/hr", dist)
                            )
                            .foregroundStyle(item.standardDrinks > 0.5 ? Color.accentColor : Color.orange)
                            .symbolSize(item.standardDrinks > 0.5 ? 30 : 15)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartForegroundStyleScale([
                    "Disturbances (events/hr)": Color.orange,
                    "Drinks": Color.accentColor.opacity(0.3),
                ])
                .frame(height: Layout.chartFrameHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Alcohol and breathing disturbances correlation. Average on drinking nights: \(String(format: "%.1f", avgDistDrinking ?? 0)) events per hour. Sober nights: \(String(format: "%.1f", avgDistSober ?? 0)) events per hour")

                let distDiff = pctDifference(avgDistSober, avgDistDrinking)

                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Drinking Nights")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(String(format: "%.1f/hr", avgDistDrinking ?? 0))
                            .font(.subheadline.bold())
                            .foregroundColor(.accentColor)
                    }
                    VStack(spacing: 2) {
                        Text("Sober Nights")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(String(format: "%.1f/hr", avgDistSober ?? 0))
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                    }
                    if let diff = distDiff {
                        VStack(spacing: 2) {
                            Text("Difference")
                                .font(.caption2)
                                .foregroundColor(.textMuted)
                            Text(String(format: "%.1f%%", abs(diff)) + (diff < 0 ? " more" : " fewer"))
                                .font(.subheadline.bold())
                                .foregroundColor(diff < 0 ? .danger : .success)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Text("Breathing disturbances (events/hr) measured by Apple Watch during sleep. Alcohol relaxes airway muscles and increases obstruction risk.")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .cardStyle()
        }
    }

    // MARK: Alcohol Quick Add

    private var alcoholQuickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Add")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                managePresetsLink { showAlcoholPresetManager = true }
            }

            if alcoholPresets.isEmpty {
                Text("No presets configured. Tap Manage Presets to add some.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(alcoholPresets) { preset in
                            Button {
                                Task { await quickAddAlcohol(preset) }
                            } label: {
                                Text(preset.name)
                                    .font(.caption)
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.bgInput)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.cardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Quick add \(preset.name)")
                            .accessibilityHint("Logs one \(preset.name) drink")
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: Alcohol Custom Form

    @ViewBuilder
    private var alcoholNameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name").font(.caption).foregroundColor(.textMuted)
            TextField("e.g. IPA", text: $alcoName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Drink name")
        }
    }

    @ViewBuilder
    private var alcoholVolumeField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Volume").font(.caption).foregroundColor(.textMuted)
            HStack(spacing: 6) {
                TextField("12", text: $alcoVolume)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Volume in \(alcoVolumeUnit.rawValue)")
                Picker("Volume unit", selection: $alcoVolumeUnit) {
                    ForEach(VolumeUnit.allCases, id: \.self) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 80)
            }
        }
    }

    @ViewBuilder
    private var alcoholABVField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ABV %").font(.caption).foregroundColor(.textMuted)
            TextField("5.0", text: $alcoABV)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityLabel("Alcohol by volume percentage")
        }
    }

    @ViewBuilder
    private var alcoholCountField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Count").font(.caption).foregroundColor(.textMuted)
            TextField("1", text: $alcoCount)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .accessibilityLabel("Number of drinks")
        }
    }

    private var alcoholCustomForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log a Drink")
                .font(.headline)
                .foregroundColor(.textPrimary)

            // Responsive: single row when ≥ ~720pt of horizontal room,
            // otherwise 2x2 grid. ViewThatFits picks the first child that fits.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    alcoholNameField.frame(minWidth: 160)
                    alcoholVolumeField.frame(minWidth: 180)
                    alcoholABVField.frame(minWidth: 80)
                    alcoholCountField.frame(minWidth: 70)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    alcoholNameField
                    alcoholVolumeField
                    alcoholABVField
                    alcoholCountField
                }
            }

            DatePicker("Date", selection: $alcoDate, displayedComponents: .date)
                .foregroundColor(.textPrimary)

            Button {
                Task { await addCustomAlcohol() }
            } label: {
                Text("Add Drink")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(alcoName.isEmpty || alcoVolume.isEmpty || alcoABV.isEmpty)
        }
        .padding()
        .cardStyle()
    }

    // MARK: Alcohol History

    private var alcoholHistory: some View {
        let sorted = alcoholDrinks.sorted { $0.date > $1.date }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Drink History")
                .font(.headline)
                .foregroundColor(.textPrimary)

            if sorted.isEmpty {
                Text("No drinks logged yet.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Date").frame(width: 80, alignment: .leading)
                        Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Oz").frame(width: 44, alignment: .trailing)
                        Text("ABV").frame(width: 48, alignment: .trailing)
                        Text("Qty").frame(width: 32, alignment: .trailing)
                        Text("Grams").frame(width: 52, alignment: .trailing)
                        Text("Std").frame(width: 40, alignment: .trailing)
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, drink in
                        alcoholRow(drink, rowIndex: index)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func startEditingDrink(_ drink: AlcoholDrink) {
        editAlcoName = drink.name
        editAlcoOz = String(format: "%.1f", drink.oz)
        editAlcoABV = String(format: "%.1f", drink.abv)
        editAlcoCount = "\(drink.count)"
        editAlcoDate = drink.date
        editingDrink = drink
    }

    private func alcoholRow(_ drink: AlcoholDrink, rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            Text(displayDate(drink.date))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            Text(drink.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(String(format: "%.1f", drink.oz))
                .frame(width: 44, alignment: .trailing)
            Text(String(format: "%.1f%%", drink.abv))
                .frame(width: 48, alignment: .trailing)
            Text("\(drink.count)")
                .frame(width: 32, alignment: .trailing)
            Text(String(format: "%.1f", drink.gramsAlcohol))
                .frame(width: 52, alignment: .trailing)
                .fontWeight(.semibold)
            Text(String(format: "%.1f", drink.standardDrinks))
                .frame(width: 40, alignment: .trailing)
        }
        .font(.caption)
        .foregroundColor(.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.tableRowAlt)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(drink.name): \(String(format: "%.1f", drink.gramsAlcohol)) grams, \(String(format: "%.1f", drink.standardDrinks)) standard drinks")
        .accessibilityHint("Tap to edit")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { startEditingDrink(drink) }
        .contextMenu {
            Button { startEditingDrink(drink) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Task {
                    await DataStore.shared.removeAlcoholDrink(id: drink.id)
                    await loadData()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }


    // MARK: - Nicotine Section

    @ViewBuilder
    private var nicotineSection: some View {
        nicotineQuickAdd
        nicotineStatsBar
        nicotineChart
        nicotineHeartRateCorrelation
        nicotineCustomForm
        nicotineHistory
    }

    // MARK: Nicotine Stats

    private var nicotineStatsBar: some View {
        let today = todayString()
        let todayMg = nicotineEntries.filter { $0.date == today }.reduce(0.0) { $0 + $1.totalMg }
        let avg7 = SubstanceEngine.rollingAverageMg(entries: nicotineEntries, days: 7)
        let avg30 = SubstanceEngine.rollingAverageMg(entries: nicotineEntries, days: 30)
        let weeklyTotal = SubstanceEngine.weeklyTotalMg(entries: nicotineEntries)
        let allTimeAvg = SubstanceEngine.allTimeAverageMg(entries: nicotineEntries)

        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                statItem(label: "Today", value: String(format: "%.1fmg", todayMg))
                Divider().frame(height: 40)
                statItem(label: "7d Avg", value: String(format: "%.1fmg", avg7))
                Divider().frame(height: 40)
                statItem(label: "30d Avg", value: String(format: "%.1fmg", avg30))
            }

            HStack(spacing: 0) {
                statItem(label: "Weekly", value: String(format: "%.1fmg", weeklyTotal))
                Divider().frame(height: 40)
                statItem(label: "All-time Avg", value: String(format: "%.1fmg", allTimeAvg))
                Divider().frame(height: 40)
                statItem(label: "", value: "")  // Placeholder for symmetry
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: Nicotine Chart

    private var nicotineChart: some View {
        let days = last30DayStrings()
        let dailyData: [DailyAmount] = days.map { day in
            let mg = nicotineEntries.filter { $0.date == day }.reduce(0.0) { $0 + $1.totalMg }
            return DailyAmount(date: day, amount: mg)
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Daily Nicotine (30 days)")
                .font(.headline)
                .foregroundColor(.textPrimary)

            Chart(dailyData) { item in
                BarMark(
                    x: .value("Date", item.date),
                    y: .value("mg", item.amount)
                )
                .foregroundStyle(Color.warning.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                }
            }
            .chartYAxisLabel("mg")
            .frame(height: Layout.chartFrameHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily nicotine consumption chart showing milligrams over the last 30 days")
        }
        .padding()
        .cardStyle()
    }

    // MARK: Nicotine + Heart Rate Correlation

    private struct NicotineHRCorrelation {
        let correlationData: [(date: String, hr: Double?, rhr: Double?, nicotineMg: Double)]
        let highLabel: String
        let lowLabel: String
        let avgHigh: Double
        let avgLow: Double
        let hasData: Bool
        let explanation: String
    }

    private func buildNicotineHRCorrelation() -> NicotineHRCorrelation {
        let days = last30DayStrings()
        let nicoByDate = Dictionary(grouping: nicotineEntries, by: \.date)

        let correlationData: [(date: String, hr: Double?, rhr: Double?, nicotineMg: Double)] = days.map { day in
            let metric = metricsByDate[day]
            let mg = (nicoByDate[day] ?? []).reduce(0.0) { $0 + $1.totalMg }
            return (day, metric?.heartRate, metric?.restingHeartRate, mg)
        }

        // Build comparison groups. Prefer clean-vs-used when the user has enough
        // of both. For daily users (few or no zero-nicotine days), fall back to
        // a median split: high-usage days vs low-usage days.
        let daysWithHR = correlationData.filter { $0.hr != nil }
        let zeroDays = daysWithHR.filter { $0.nicotineMg == 0 }
        let usedDays = daysWithHR.filter { $0.nicotineMg > 0 }

        let cleanVsUsed = zeroDays.count >= 3 && usedDays.count >= 3
        let highGroup: [(date: String, hr: Double?, rhr: Double?, nicotineMg: Double)]
        let lowGroup: [(date: String, hr: Double?, rhr: Double?, nicotineMg: Double)]
        let highLabel: String
        let lowLabel: String
        let explanation: String

        if cleanVsUsed {
            highGroup = usedDays
            lowGroup = zeroDays
            highLabel = "Nicotine Days"
            lowLabel = "Clean Days"
            explanation = "Nicotine raises heart rate by stimulating adrenaline release."
        } else {
            // Median split on usage among days with HR data. Prefer used-only
            // days when there are enough of them.
            let pool = usedDays.count >= 4 ? usedDays : daysWithHR
            let sortedMg = pool.map(\.nicotineMg).sorted()
            let median: Double
            if sortedMg.isEmpty {
                median = 0
            } else {
                let mid = sortedMg.count / 2
                median = sortedMg.count % 2 == 0
                    ? (sortedMg[mid - 1] + sortedMg[mid]) / 2
                    : sortedMg[mid]
            }
            highGroup = pool.filter { $0.nicotineMg > median }
            lowGroup = pool.filter { $0.nicotineMg <= median }
            highLabel = "High Usage"
            lowLabel = "Low Usage"
            explanation = "Comparing your higher-usage days against your lower-usage days. Nicotine raises heart rate by stimulating adrenaline release."
        }

        let avgHigh = highGroup.isEmpty ? 0 : highGroup.compactMap(\.hr).reduce(0, +) / Double(highGroup.count)
        let avgLow = lowGroup.isEmpty ? 0 : lowGroup.compactMap(\.hr).reduce(0, +) / Double(lowGroup.count)
        let hasData = !highGroup.isEmpty && !lowGroup.isEmpty

        return NicotineHRCorrelation(
            correlationData: correlationData,
            highLabel: highLabel,
            lowLabel: lowLabel,
            avgHigh: avgHigh,
            avgLow: avgLow,
            hasData: hasData,
            explanation: explanation
        )
    }

    @ViewBuilder
    private var nicotineHeartRateCorrelation: some View {
        let model = buildNicotineHRCorrelation()
        let correlationData = model.correlationData
        let highLabel = model.highLabel
        let lowLabel = model.lowLabel
        let avgHigh = model.avgHigh
        let avgLow = model.avgLow

        if model.hasData {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nicotine + Heart Rate Correlation")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                Chart {
                    ForEach(correlationData, id: \.date) { item in
                        if let hr = item.hr {
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("bpm", hr),
                                series: .value("Metric", "Heart Rate")
                            )
                            .foregroundStyle(by: .value("Metric", "Heart Rate"))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        if let rhr = item.rhr {
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("bpm", rhr),
                                series: .value("Metric", "Resting HR")
                            )
                            .foregroundStyle(by: .value("Metric", "Resting HR"))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartYAxisLabel("bpm")
                .chartForegroundStyleScale([
                    "Heart Rate": Color.red,
                    "Resting HR": Color.blue,
                ])
                .frame(height: Layout.chartFrameHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Nicotine and heart rate correlation chart. Average heart rate on \(highLabel.lowercased()): \(String(format: "%.0f", avgHigh)) bpm. \(lowLabel): \(String(format: "%.0f", avgLow)) bpm")

                let pctDiff = avgLow > 0 ? ((avgHigh - avgLow) / avgLow * 100) : 0
                let direction = pctDiff > 0 ? "higher" : "lower"
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(highLabel)
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(String(format: "%.0f bpm", avgHigh))
                            .font(.subheadline.bold())
                            .foregroundColor(.warning)
                    }
                    VStack(spacing: 2) {
                        Text(lowLabel)
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(String(format: "%.0f bpm", avgLow))
                            .font(.subheadline.bold())
                            .foregroundColor(.success)
                    }
                    VStack(spacing: 2) {
                        Text("Difference")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(String(format: "%.1f%% %@", abs(pctDiff), direction))
                            .font(.subheadline.bold())
                            .foregroundColor(pctDiff > 0 ? .danger : .success)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(model.explanation)
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .cardStyle()
        }
    }

    // MARK: Nicotine Quick Add

    private var nicotineQuickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Add")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                managePresetsLink { showNicotinePresetManager = true }
            }

            if nicotinePresets.isEmpty {
                Text("No presets configured. Tap Manage Presets to add some.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(nicotinePresets) { preset in
                            Button {
                                Task { await quickAddNicotine(preset) }
                            } label: {
                                Text(preset.name)
                                    .font(.caption)
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.bgInput)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.cardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Quick add \(preset.name)")
                            .accessibilityHint("Logs one \(preset.name) nicotine entry")
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: Nicotine Custom Form

    @ViewBuilder
    private var nicotineProductField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Product").font(.caption).foregroundColor(.textMuted)
            TextField("e.g. Zyn 6mg", text: $nicoProduct)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Nicotine product name")
        }
    }

    @ViewBuilder
    private var nicotineMgField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("mg / unit").font(.caption).foregroundColor(.textMuted)
            TextField("6", text: $nicoMgPerUnit)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityLabel("Milligrams per unit")
        }
    }

    @ViewBuilder
    private var nicotineCountField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Count").font(.caption).foregroundColor(.textMuted)
            TextField("1", text: $nicoCount)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .accessibilityLabel("Number of units")
        }
    }

    @ViewBuilder
    private var nicotineDateField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Date").font(.caption).foregroundColor(.textMuted)
            DatePicker("", selection: $nicoDate, displayedComponents: .date)
                .labelsHidden()
        }
    }

    private var nicotineCustomForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Nicotine")
                .font(.headline)
                .foregroundColor(.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    nicotineProductField.frame(minWidth: 160)
                    nicotineMgField.frame(minWidth: 90)
                    nicotineCountField.frame(minWidth: 70)
                    nicotineDateField.frame(minWidth: 150)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    nicotineProductField
                    nicotineMgField
                    nicotineCountField
                    nicotineDateField
                }
            }

            Button {
                Task { await addCustomNicotine() }
            } label: {
                Text("Add Entry")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.warning)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(nicoProduct.isEmpty || nicoMgPerUnit.isEmpty)
        }
        .padding()
        .cardStyle()
    }

    // MARK: Nicotine History

    private var nicotineHistory: some View {
        let sorted = nicotineEntries.sorted { $0.date > $1.date }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Nicotine History")
                .font(.headline)
                .foregroundColor(.textPrimary)

            if sorted.isEmpty {
                Text("No entries logged yet.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Date").frame(width: 80, alignment: .leading)
                        Text("Product").frame(maxWidth: .infinity, alignment: .leading)
                        Text("mg/unit").frame(width: 60, alignment: .trailing)
                        Text("Qty").frame(width: 36, alignment: .trailing)
                        Text("Total mg").frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, entry in
                        nicotineRow(entry, rowIndex: index)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func startEditingNicotine(_ entry: NicotineEntry) {
        editNicoProduct = entry.product
        editNicoMg = String(format: "%.1f", entry.mgPerUnit)
        editNicoCount = "\(entry.count)"
        editNicoDate = entry.date
        editingNicotine = entry
    }

    private func nicotineRow(_ entry: NicotineEntry, rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            Text(displayDate(entry.date))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            Text(entry.product)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(String(format: "%.1f", entry.mgPerUnit))
                .frame(width: 60, alignment: .trailing)
            Text("\(entry.count)")
                .frame(width: 36, alignment: .trailing)
            Text(String(format: "%.1f", entry.totalMg))
                .frame(width: 64, alignment: .trailing)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundColor(.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.tableRowAlt)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.product): \(String(format: "%.1f", entry.totalMg)) milligrams total, \(String(format: "%.1f", entry.mgPerUnit)) mg per unit, \(entry.count) units")
        .accessibilityHint("Tap to edit")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { startEditingNicotine(entry) }
        .contextMenu {
            Button { startEditingNicotine(entry) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Task {
                    await DataStore.shared.removeNicotineEntry(id: entry.id)
                    await loadData()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }


    // MARK: - Sauna Section

    @ViewBuilder
    private var saunaSection: some View {
        saunaQuickAdd
        saunaStatsBar
        saunaChart
        saunaRecoveryCorrelation
        saunaCustomForm
        saunaHistory
    }

    // MARK: Sauna Stats

    private var saunaStatsBar: some View {
        let today = todayString()
        let todayMin = saunaSessions.filter { $0.date == today }.reduce(0) { $0 + $1.durationMinutes }
        let avg7 = SubstanceEngine.rollingAverageMinutes(sessions: saunaSessions, days: 7)
        let avg30 = SubstanceEngine.rollingAverageMinutes(sessions: saunaSessions, days: 30)
        let weeklyCount = SubstanceEngine.weeklySessionCount(sessions: saunaSessions)
        let weeklyMin = SubstanceEngine.weeklyTotalMinutes(sessions: saunaSessions)

        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                statItem(label: "Today", value: "\(todayMin)m")
                Divider().frame(height: 40)
                statItem(label: "7d Avg", value: String(format: "%.0fm", avg7))
                Divider().frame(height: 40)
                statItem(label: "30d Avg", value: String(format: "%.0fm", avg30))
            }
            HStack(spacing: 0) {
                statItem(label: "This Week", value: "\(weeklyMin)m")
                Divider().frame(height: 40)
                statItem(label: "Sessions/Wk", value: "\(weeklyCount)")
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: Sauna Chart

    private var saunaChart: some View {
        let days = last30DayStrings()
        let grouped = Dictionary(grouping: saunaSessions, by: \.date)
        let points = days.map { day in
            DailyAmount(date: day, amount: Double(grouped[day]?.reduce(0) { $0 + $1.durationMinutes } ?? 0))
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Daily Sauna (30 days)")
                .font(.headline)
                .foregroundColor(.textPrimary)

            Chart(points) { point in
                BarMark(
                    x: .value("Date", point.date),
                    y: .value("Minutes", point.amount)
                )
                .foregroundStyle(Color.orange.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                }
            }
            .chartYAxisLabel("minutes")
            .frame(height: Layout.chartFrameHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily sauna duration chart showing minutes over the last 30 days")
        }
        .padding()
        .cardStyle()
    }

    // MARK: Sauna + Recovery Correlation

    @ViewBuilder
    private var saunaRecoveryCorrelation: some View {
        let dataPoints = CorrelationEngine.saunaRecoveryCorrelation(
            sessions: saunaSessions,
            healthMetrics: healthMetrics
        )

        let saunaDays = dataPoints.filter { $0.saunaMinutes > 0 }
        let restDays = dataPoints.filter { $0.saunaMinutes == 0 }

        let avgHRVSauna = average(saunaDays.compactMap(\.nextDayHRV))
        let avgHRVRest = average(restDays.compactMap(\.nextDayHRV))
        let avgDeepSauna = average(saunaDays.compactMap(\.nextNightDeepPct))
        let avgDeepRest = average(restDays.compactMap(\.nextNightDeepPct))
        let avgRemSauna = average(saunaDays.compactMap(\.nextNightRemPct))
        let avgRemRest = average(restDays.compactMap(\.nextNightRemPct))

        let hasData = !saunaDays.isEmpty && !restDays.isEmpty
            && (avgHRVSauna != nil && avgHRVRest != nil
                || avgDeepSauna != nil && avgDeepRest != nil)

        if hasData {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sauna + Recovery (HRV & Sleep)")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                let chartData = dataPoints.suffix(60)

                Chart {
                    ForEach(Array(chartData), id: \.date) { item in
                        if item.saunaMinutes > 0 {
                            BarMark(
                                x: .value("Date", item.date),
                                y: .value("Minutes", item.saunaMinutes)
                            )
                            .foregroundStyle(Color.orange.opacity(0.3))
                        }
                        if let hrv = item.nextDayHRV {
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("HRV", hrv),
                                series: .value("Metric", "HRV (ms)")
                            )
                            .foregroundStyle(Color.green)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        if let deep = item.nextNightDeepPct {
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("Deep %", deep),
                                series: .value("Metric", "Deep Sleep %")
                            )
                            .foregroundStyle(Color.indigo)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartForegroundStyleScale([
                    "HRV (ms)": Color.green,
                    "Deep Sleep %": Color.indigo,
                    "Sauna": Color.orange.opacity(0.3),
                ])
                .frame(height: Layout.chartFrameHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sauna and recovery correlation. HRV after sauna: \(String(format: "%.0f", avgHRVSauna ?? 0)) ms. Rest days: \(String(format: "%.0f", avgHRVRest ?? 0)) ms. Deep sleep after sauna: \(String(format: "%.1f", avgDeepSauna ?? 0))%. Rest days: \(String(format: "%.1f", avgDeepRest ?? 0))%")

                // Summary stats
                let hrvDiff = pctDifference(avgHRVRest, avgHRVSauna)
                let deepDiff = pctDifference(avgDeepRest, avgDeepSauna)
                let remDiff = pctDifference(avgRemRest, avgRemSauna)

                VStack(spacing: 8) {
                    if let hSauna = avgHRVSauna, let hRest = avgHRVRest {
                        HStack(spacing: 12) {
                            sleepStatColumn(
                                label: "HRV (Sauna)",
                                value: String(format: "%.0f ms", hSauna),
                                color: .orange
                            )
                            sleepStatColumn(
                                label: "HRV (Rest)",
                                value: String(format: "%.0f ms", hRest),
                                color: .green
                            )
                            sleepStatColumn(
                                label: "HRV Δ",
                                value: String(format: "%.1f%%", abs(hrvDiff ?? 0)) + (hrvDiff.map { $0 < 0 ? " higher" : " lower" } ?? ""),
                                color: (hrvDiff ?? 0) < 0 ? .success : .danger
                            )
                        }
                    }
                    if avgDeepSauna != nil && avgDeepRest != nil {
                        HStack(spacing: 12) {
                            sleepStatColumn(
                                label: "Deep (Sauna)",
                                value: String(format: "%.1f%%", avgDeepSauna ?? 0),
                                color: .orange
                            )
                            sleepStatColumn(
                                label: "Deep (Rest)",
                                value: String(format: "%.1f%%", avgDeepRest ?? 0),
                                color: .indigo
                            )
                            sleepStatColumn(
                                label: "Deep Δ",
                                value: String(format: "%.1f%%", abs(deepDiff ?? 0)) + (deepDiff.map { $0 < 0 ? " more" : " less" } ?? ""),
                                color: (deepDiff ?? 0) < 0 ? .success : .danger
                            )
                        }
                    }
                    if avgRemSauna != nil && avgRemRest != nil {
                        HStack(spacing: 12) {
                            sleepStatColumn(
                                label: "REM (Sauna)",
                                value: String(format: "%.1f%%", avgRemSauna ?? 0),
                                color: .orange
                            )
                            sleepStatColumn(
                                label: "REM (Rest)",
                                value: String(format: "%.1f%%", avgRemRest ?? 0),
                                color: .purple
                            )
                            sleepStatColumn(
                                label: "REM Δ",
                                value: String(format: "%.1f%%", abs(remDiff ?? 0)) + (remDiff.map { $0 < 0 ? " more" : " less" } ?? ""),
                                color: (remDiff ?? 0) < 0 ? .success : .danger
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Text("Sauna use may improve HRV and deep sleep via heat stress adaptation and parasympathetic activation.")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .cardStyle()
        }
    }

    // MARK: Sauna Quick Add

    private var saunaQuickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "QUICK ADD")
                Spacer()
                managePresetsLink { showSaunaPresetManager = true }
            }
            if saunaPresets.isEmpty {
                Text("No presets. Tap Manage Presets to add some.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(saunaPresets) { preset in
                            Button {
                                Task { await quickAddSauna(preset) }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: preset.saunaType == .infrared ? "light.max" : "cloud.fill")
                                        .font(.title3)
                                    Text(preset.name)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 100, height: 70)
                                .foregroundColor(.textPrimary)
                                .background(Color.bgInput)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.cardBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Quick add \(preset.name)")
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: Sauna Custom Form

    private var saunaCustomForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "LOG SESSION")

            VStack(spacing: 10) {
                Picker("Type", selection: $saunaType) {
                    ForEach(SaunaType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: saunaType) { _, newType in
                    saunaTemp = "\(newType.defaultTempF)"
                    saunaDuration = "\(newType.defaultMinutes)"
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Temp (\u{00B0}F)")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        TextField("Temp", text: $saunaTemp)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .accessibilityLabel("Temperature in Fahrenheit")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Minutes")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        TextField("Duration", text: $saunaDuration)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .accessibilityLabel("Duration in minutes")
                    }
                }

                DatePicker("Date", selection: $saunaDate, displayedComponents: .date)
                    .font(.subheadline)

                Button {
                    Task { await addCustomSauna() }
                } label: {
                    Text("Log Session")
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(saunaTemp.isEmpty || saunaDuration.isEmpty)
            }
            .padding()
            .cardStyle()
        }
    }

    private func startEditingSauna(_ session: SaunaSession) {
        editSaunaType = session.saunaType
        editSaunaTemp = "\(session.temperatureF)"
        editSaunaDuration = "\(session.durationMinutes)"
        editSaunaDate = session.date
        editingSauna = session
    }

    // MARK: Sauna History

    @ViewBuilder
    private var saunaHistory: some View {
        let sorted = saunaSessions.sorted { $0.date > $1.date }

        if !sorted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "HISTORY")
                LazyVStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Date").frame(width: 80, alignment: .leading)
                        Text("Type").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Temp").frame(width: 56, alignment: .trailing)
                        Text("Duration").frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    ForEach(Array(sorted.prefix(30).enumerated()), id: \.element.id) { index, session in
                        saunaRow(session, rowIndex: index)
                    }
                }
            }
        }
    }

    private func saunaRow(_ session: SaunaSession, rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            Text(displayDate(session.date))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: session.saunaType == .infrared ? "light.max" : "cloud.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text(session.saunaType.rawValue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(session.temperatureF)\u{00B0}F")
                .frame(width: 56, alignment: .trailing)
            Text("\(session.durationMinutes) min")
                .frame(width: 64, alignment: .trailing)
        }
        .font(.caption)
        .foregroundColor(.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.tableRowAlt)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.saunaType.rawValue) sauna: \(session.temperatureF) degrees Fahrenheit for \(session.durationMinutes) minutes")
        .accessibilityHint("Tap to edit")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { startEditingSauna(session) }
        .contextMenu {
            Button { startEditingSauna(session) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Task {
                    await DataStore.shared.removeSaunaSession(id: session.id)
                    await loadData()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }


    // MARK: Sauna Edit Sheet

    private func saunaEditSheet(_ session: SaunaSession) -> some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $editSaunaType) {
                    ForEach(SaunaType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                TextField("Temperature (\u{00B0}F)", text: $editSaunaTemp)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("Duration (minutes)", text: $editSaunaDuration)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("Date (YYYY-MM-DD)", text: $editSaunaDate)

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .macGroupedFormStyle()
            .macSheetFrame(minHeight: 360, idealHeight: 480)
            .navigationTitle("Edit Session")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingSauna = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let temp = Int(editSaunaTemp),
                              let dur = Int(editSaunaDuration) else { return }
                        let updated = SaunaSession(
                            id: session.id,
                            saunaType: editSaunaType,
                            temperatureF: temp,
                            durationMinutes: dur,
                            date: editSaunaDate
                        )
                        Task {
                            await DataStore.shared.updateSaunaSession(updated)
                            await loadData()
                        }
                        editingSauna = nil
                    }
                }
            }
            .alert("Delete Session", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        await DataStore.shared.removeSaunaSession(id: session.id)
                        await loadData()
                    }
                    editingSauna = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this sauna session?")
            }
        }
    }

    // MARK: - Shared UI Components

    private func managePresetsLink(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                Text("Manage Presets")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func statItem(label: String, value: String, valueColor: Color = .textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.textMuted)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Edit Sheets

    private func alcoholEditSheet(_ drink: AlcoholDrink) -> some View {
        NavigationStack {
            Form {
                Section("Drink") {
                    TextField("Name", text: $editAlcoName)
                    TextField("Oz", text: $editAlcoOz)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("ABV %", text: $editAlcoABV)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Count", text: $editAlcoCount)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Date (YYYY-MM-DD)", text: $editAlcoDate)
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Drink", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    #endif
                }
            }
            .macGroupedFormStyle()
            .macSheetFrame(minHeight: 360, idealHeight: 480)
            .navigationTitle("Edit Drink")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingDrink = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let oz = Double(editAlcoOz),
                              let abv = Double(editAlcoABV),
                              let count = Int(editAlcoCount) else { return }
                        let updated = AlcoholDrink(
                            id: drink.id,
                            name: editAlcoName,
                            oz: oz,
                            abv: abv,
                            count: count,
                            date: editAlcoDate
                        )
                        Task {
                            await DataStore.shared.updateAlcoholDrink(updated)
                            await loadData()
                        }
                        editingDrink = nil
                    }
                }
            }
            .alert("Delete Drink", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        await DataStore.shared.removeAlcoholDrink(id: drink.id)
                        await loadData()
                    }
                    editingDrink = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this drink?")
            }
        }
    }

    private func nicotineEditSheet(_ entry: NicotineEntry) -> some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    TextField("Product", text: $editNicoProduct)
                    TextField("mg/unit", text: $editNicoMg)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Count", text: $editNicoCount)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Date (YYYY-MM-DD)", text: $editNicoDate)
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Entry", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    #endif
                }
            }
            .macGroupedFormStyle()
            .macSheetFrame(minHeight: 360, idealHeight: 480)
            .navigationTitle("Edit Entry")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingNicotine = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let mg = Double(editNicoMg),
                              let count = Int(editNicoCount) else { return }
                        let updated = NicotineEntry(
                            id: entry.id,
                            product: editNicoProduct,
                            mgPerUnit: mg,
                            count: count,
                            date: editNicoDate
                        )
                        Task {
                            await DataStore.shared.updateNicotineEntry(updated)
                            await loadData()
                        }
                        editingNicotine = nil
                    }
                }
            }
            .alert("Delete Entry", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        await DataStore.shared.removeNicotineEntry(id: entry.id)
                        await loadData()
                    }
                    editingNicotine = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this nicotine entry?")
            }
        }
    }

    // MARK: - Actions

    private func quickAddAlcohol(_ preset: AlcoholPreset) async {
        let today = todayString()
        if var existing = alcoholDrinks.first(where: { $0.name == preset.name && $0.oz == preset.oz && $0.abv == preset.abv && $0.date == today }) {
            existing.count += 1
            await DataStore.shared.updateAlcoholDrink(existing)
        } else {
            let drink = AlcoholDrink(name: preset.name, oz: preset.oz, abv: preset.abv, count: 1, date: today)
            await DataStore.shared.addAlcoholDrink(drink)
        }
        await loadData()
        showToast($toastMessage, message: "\(preset.name) logged")
    }

    private func addCustomAlcohol() async {
        guard let volume = Double(alcoVolume),
              let abv = Double(alcoABV),
              let count = Int(alcoCount) else { return }
        let oz = volume * alcoVolumeUnit.toOz
        let drink = AlcoholDrink(
            name: alcoName,
            oz: oz,
            abv: abv,
            count: count,
            date: DateFormatting.dateString( alcoDate)
        )
        await DataStore.shared.addAlcoholDrink(drink)
        let name = alcoName.isEmpty ? "Drink" : alcoName
        alcoName = ""
        alcoVolume = ""
        alcoABV = ""
        alcoCount = "1"
        alcoDate = Date()
        await loadData()
        showToast($toastMessage, message: "\(name) logged")
    }

    private func quickAddNicotine(_ preset: NicotinePreset) async {
        let today = todayString()
        if var existing = nicotineEntries.first(where: { $0.product == preset.name && $0.mgPerUnit == preset.mgPerUnit && $0.date == today }) {
            existing.count += 1
            await DataStore.shared.updateNicotineEntry(existing)
        } else {
            let entry = NicotineEntry(product: preset.name, mgPerUnit: preset.mgPerUnit, count: 1, date: today)
            await DataStore.shared.addNicotineEntry(entry)
        }
        await loadData()
        showToast($toastMessage, message: "\(preset.name) logged")
    }

    private func addCustomNicotine() async {
        guard let mg = Double(nicoMgPerUnit),
              let count = Int(nicoCount) else { return }
        let entry = NicotineEntry(
            product: nicoProduct,
            mgPerUnit: mg,
            count: count,
            date: DateFormatting.dateString( nicoDate)
        )
        await DataStore.shared.addNicotineEntry(entry)
        let name = nicoProduct.isEmpty ? "Nicotine" : nicoProduct
        nicoProduct = ""
        nicoMgPerUnit = ""
        nicoCount = "1"
        nicoDate = Date()
        await loadData()
        showToast($toastMessage, message: "\(name) logged")
    }

    private func quickAddSauna(_ preset: SaunaPreset) async {
        let session = SaunaSession(
            saunaType: preset.saunaType,
            temperatureF: preset.temperatureF,
            durationMinutes: preset.durationMinutes,
            date: todayString()
        )
        await DataStore.shared.addSaunaSession(session)
        await loadData()
        showToast($toastMessage, message: "\(preset.saunaType.rawValue.capitalized) sauna logged")
    }

    private func addCustomSauna() async {
        guard let temp = Int(saunaTemp),
              let dur = Int(saunaDuration) else { return }
        let session = SaunaSession(
            saunaType: saunaType,
            temperatureF: temp,
            durationMinutes: dur,
            date: DateFormatting.dateString(saunaDate)
        )
        await DataStore.shared.addSaunaSession(session)
        saunaTemp = "\(saunaType.defaultTempF)"
        saunaDuration = "\(saunaType.defaultMinutes)"
        saunaDate = Date()
        await loadData()
        showToast($toastMessage, message: "\(saunaType.rawValue.capitalized) sauna logged")
    }

}

// MARK: - Alcohol Preset Manager

struct AlcoholPresetManagerView: View {
    @Binding var presets: [AlcoholPreset]
    let onSave: ([AlcoholPreset]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newOz = ""
    @State private var newABV = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Existing Presets") {
                    ForEach(presets) { preset in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                    .font(.subheadline)
                                Text("\(String(format: "%.1f", preset.oz))oz, \(String(format: "%.1f", preset.abv))%")
                                    .font(.caption)
                                    .foregroundColor(.textMuted)
                            }
                            Spacer()
                        }
                    }
                    .onDelete { indexSet in
                        presets.remove(atOffsets: indexSet)
                    }
                    .onMove { from, to in
                        presets.move(fromOffsets: from, toOffset: to)
                    }
                }

                Section("Add Preset") {
                    TextField("Name", text: $newName)
                    TextField("Oz", text: $newOz)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("ABV %", text: $newABV)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Button("Add") {
                        guard let oz = Double(newOz), let abv = Double(newABV), !newName.isEmpty else { return }
                        presets.append(AlcoholPreset(name: newName, oz: oz, abv: abv))
                        newName = ""
                        newOz = ""
                        newABV = ""
                    }
                    .disabled(newName.isEmpty || newOz.isEmpty || newABV.isEmpty)
                }

                Section {
                    Button("Reset to Defaults") {
                        presets = AlcoholPreset.defaults
                    }
                    .foregroundColor(.danger)
                }
            }
            .navigationTitle("Alcohol Presets")
            .inlineNavigationTitle()
            .macSheetFrame(minHeight: 480, idealHeight: 560)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(presets)
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                #endif
            }
        }
    }
}

// MARK: - Nicotine Preset Manager

struct NicotinePresetManagerView: View {
    @Binding var presets: [NicotinePreset]
    let onSave: ([NicotinePreset]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newMg = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Existing Presets") {
                    ForEach(presets) { preset in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                    .font(.subheadline)
                                Text("\(String(format: "%.1f", preset.mgPerUnit))mg")
                                    .font(.caption)
                                    .foregroundColor(.textMuted)
                            }
                            Spacer()
                        }
                    }
                    .onDelete { indexSet in
                        presets.remove(atOffsets: indexSet)
                    }
                    .onMove { from, to in
                        presets.move(fromOffsets: from, toOffset: to)
                    }
                }

                Section("Add Preset") {
                    TextField("Product Name", text: $newName)
                    TextField("mg per unit", text: $newMg)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Button("Add") {
                        guard let mg = Double(newMg), !newName.isEmpty else { return }
                        presets.append(NicotinePreset(name: newName, mgPerUnit: mg))
                        newName = ""
                        newMg = ""
                    }
                    .disabled(newName.isEmpty || newMg.isEmpty)
                }
            }
            .navigationTitle("Nicotine Presets")
            .inlineNavigationTitle()
            .macSheetFrame(minHeight: 480, idealHeight: 560)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(presets)
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                #endif
            }
        }
    }
}

// MARK: - Sauna Preset Manager

struct SaunaPresetManagerView: View {
    @Binding var presets: [SaunaPreset]
    let onSave: ([SaunaPreset]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newType: SaunaType = .infrared
    @State private var newTemp = "140"
    @State private var newDuration = "25"

    var body: some View {
        NavigationStack {
            List {
                Section("Existing Presets") {
                    ForEach(presets) { preset in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                    .font(.subheadline)
                                Text("\(preset.saunaType.rawValue) \u{2022} \(preset.temperatureF)\u{00B0}F \u{2022} \(preset.durationMinutes) min")
                                    .font(.caption)
                                    .foregroundColor(.textMuted)
                            }
                            Spacer()
                        }
                    }
                    .onDelete { indexSet in
                        presets.remove(atOffsets: indexSet)
                    }
                    .onMove { from, to in
                        presets.move(fromOffsets: from, toOffset: to)
                    }
                }

                Section("Add Preset") {
                    TextField("Name", text: $newName)
                    Picker("Type", selection: $newType) {
                        ForEach(SaunaType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: newType) { _, type in
                        newTemp = "\(type.defaultTempF)"
                        newDuration = "\(type.defaultMinutes)"
                    }
                    TextField("Temperature (\u{00B0}F)", text: $newTemp)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Duration (min)", text: $newDuration)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button("Add") {
                        guard let temp = Int(newTemp), let dur = Int(newDuration), !newName.isEmpty else { return }
                        presets.append(SaunaPreset(name: newName, saunaType: newType, temperatureF: temp, durationMinutes: dur))
                        newName = ""
                        newTemp = "\(newType.defaultTempF)"
                        newDuration = "\(newType.defaultMinutes)"
                    }
                    .disabled(newName.isEmpty || newTemp.isEmpty || newDuration.isEmpty)
                }

                Section {
                    Button("Reset to Defaults") {
                        presets = SaunaPreset.defaults
                    }
                    .foregroundColor(.danger)
                }
            }
            .navigationTitle("Sauna Presets")
            .inlineNavigationTitle()
            .macSheetFrame(minHeight: 480, idealHeight: 560)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(presets)
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                #endif
            }
        }
    }
}
