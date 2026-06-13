import SwiftUI
import Charts

// MARK: - AlcoholView

/// Alcohol tracker tab: quick-add, stats, charts (consumption + HRV / sleep /
/// breathing correlations), custom logging, and history. Owns only alcohol state.
struct AlcoholView: View {
    @State private var alcoholDrinks: [AlcoholDrink] = []
    @State private var alcoholPresets: [AlcoholPreset] = []
    @State private var biologicalSex: BiologicalSex?

    // Health metrics for correlation charts
    @State private var healthMetrics: [HealthMetricEntry] = []
    private var metricsByDate: [String: HealthMetricEntry] {
        Dictionary(healthMetrics.map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    // Form
    @State private var alcoName = ""
    @State private var alcoVolume = ""
    @State private var alcoVolumeUnit: VolumeUnit = .oz
    @State private var alcoABV = ""
    @State private var alcoCount = "1"
    @State private var alcoDate = Date()

    // Edit sheet
    @State private var editingDrink: AlcoholDrink?
    @State private var showDeleteConfirm = false
    @State private var showAlcoholPresetManager = false
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }

    @State private var toastMessage: String?

    // Edit form state
    @State private var editAlcoName = ""
    @State private var editAlcoOz = ""
    @State private var editAlcoABV = ""
    @State private var editAlcoCount = ""
    @State private var editAlcoDate = ""

    var body: some View {
        VStack(spacing: 16) {
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
        .padding()
        .readContainerWidth { containerWidth = $0 }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
        .sheet(item: $editingDrink) { drink in
            alcoholEditSheet(drink)
        }
        .sheet(isPresented: $showAlcoholPresetManager) {
            AlcoholPresetManagerView(presets: $alcoholPresets, onSave: { newPresets in
                Task { await DataStore.shared.setAlcoholPresets(newPresets) }
            })
        }
        .toast($toastMessage)
    }

    // MARK: - Data Loading

    private func loadData() async {
        let data = await DataStore.shared.getData()
        alcoholDrinks = data.alcoholDrinks
        alcoholPresets = data.alcoholPresets
        biologicalSex = data.profile.biologicalSex
        healthMetrics = data.healthMetrics
    }

    // MARK: Alcohol Stats

    private var alcoholStatsBar: some View {
        let today = substanceTodayString()
        let todayGrams = alcoholDrinks.filter { $0.date == today }.reduce(0.0) { $0 + $1.gramsAlcohol }
        let avg7 = SubstanceEngine.rollingAverageGrams(drinks: alcoholDrinks, days: 7)
        let avg30 = SubstanceEngine.rollingAverageGrams(drinks: alcoholDrinks, days: 30)
        let weeklyTotal = SubstanceEngine.weeklyTotalStandardDrinks(drinks: alcoholDrinks)
        let allTimeAvg = SubstanceEngine.allTimeAverageGrams(drinks: alcoholDrinks)
        let risk = SubstanceEngine.alcoholRisk(drinks: alcoholDrinks, sex: biologicalSex)
        let weeklyThreshold: Double = (biologicalSex == .female) ? 7.0 : 14.0

        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                substanceStatItem(label: "Today", value: String(format: "%.1fg", todayGrams))
                Divider().frame(height: 40)
                substanceStatItem(label: "7d Avg", value: String(format: "%.1fg", avg7))
                Divider().frame(height: 40)
                substanceStatItem(label: "30d Avg", value: String(format: "%.1fg", avg30))
            }

            HStack(spacing: 0) {
                substanceStatItem(
                    label: "Std Drinks/wk",
                    value: String(format: "%.1f / %.0f max", weeklyTotal, weeklyThreshold),
                    valueColor: weeklyTotal > weeklyThreshold ? .danger : .success
                )
                Divider().frame(height: 40)
                substanceStatItem(label: "All-time Avg", value: String(format: "%.1fg", allTimeAvg))
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
        let avgDrinking = drinkingDays.compactAverage(\.hrv) ?? 0
        let avgSober = soberDays.compactAverage(\.hrv) ?? 0
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

        let avgDeepDrinking = substanceAverage(drinkingDays.compactMap(\.nextNightDeepPct))
        let avgDeepSober = substanceAverage(soberDays.compactMap(\.nextNightDeepPct))
        let avgRemDrinking = substanceAverage(drinkingDays.compactMap(\.nextNightRemPct))
        let avgRemSober = substanceAverage(soberDays.compactMap(\.nextNightRemPct))
        let avgHoursDrinking = substanceAverage(drinkingDays.compactMap(\.nextNightTotalHours))
        let avgHoursSober = substanceAverage(soberDays.compactMap(\.nextNightTotalHours))

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
                let deepDiff = substancePctDifference(avgDeepSober, avgDeepDrinking)
                let remDiff = substancePctDifference(avgRemSober, avgRemDrinking)
                let hoursDiff = substancePctDifference(avgHoursSober, avgHoursDrinking)

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

    // MARK: Alcohol + Breathing Disturbances Correlation

    @ViewBuilder
    private var alcoholBreathingCorrelation: some View {
        let dataPoints = CorrelationEngine.alcoholBreathingCorrelation(
            drinks: alcoholDrinks,
            healthMetrics: healthMetrics
        )

        let drinkingDays = dataPoints.filter { $0.standardDrinks > 0.5 }
        let soberDays = dataPoints.filter { $0.standardDrinks <= 0.5 }

        let avgDistDrinking = substanceAverage(drinkingDays.compactMap(\.nextNightDisturbances))
        let avgDistSober = substanceAverage(soberDays.compactMap(\.nextNightDisturbances))

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

                let distDiff = substancePctDifference(avgDistSober, avgDistDrinking)

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
                            .accessibilityHint("Logs one \(preset.name) drink. Drag to reorder.")
                            .modifier(ReorderableChip(preset: preset, presets: $alcoholPresets) { saved in Task { await DataStore.shared.setAlcoholPresets(saved) } })
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
            Text(substanceDisplayDate(drink.date))
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

    // MARK: Alcohol Edit Sheet

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

    // MARK: - Actions

    private func quickAddAlcohol(_ preset: AlcoholPreset) async {
        let today = substanceTodayString()
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
            date: DateFormatting.dateString(alcoDate)
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
