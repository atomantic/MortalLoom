import SwiftUI
import Charts

// MARK: - SaunaView

/// Sauna tracker tab: quick-add, stats, consumption + recovery (HRV / sleep)
/// correlation charts, custom logging, and history. Owns only sauna state.
struct SaunaView: View {
    @State private var saunaSessions: [SaunaSession] = []
    @State private var saunaPresets: [SaunaPreset] = []

    // Health metrics for correlation charts
    @State private var healthMetrics: [HealthMetricEntry] = []

    // Form
    @State private var saunaType: SaunaType = .infrared
    @State private var saunaTemp = "140"
    @State private var saunaDuration = "25"
    @State private var saunaDate = Date()

    // Edit sheet
    @State private var editingSauna: SaunaSession?
    @State private var showDeleteConfirm = false
    @State private var showSaunaPresetManager = false

    @State private var toastMessage: String?

    // Edit form state
    @State private var editSaunaType: SaunaType = .infrared
    @State private var editSaunaTemp = ""
    @State private var editSaunaDuration = ""
    @State private var editSaunaDate = ""

    var body: some View {
        VStack(spacing: 16) {
            saunaQuickAdd
            saunaStatsBar
            saunaChart
            saunaRecoveryCorrelation
            saunaCustomForm
            saunaHistory
        }
        .padding()
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
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
        healthMetrics = data.healthMetrics
        saunaSessions = data.saunaSessions
        saunaPresets = data.saunaPresets
    }

    // MARK: Sauna Stats

    private var saunaStatsBar: some View {
        let today = substanceTodayString()
        let todayMin = saunaSessions.filter { $0.date == today }.reduce(0) { $0 + $1.durationMinutes }
        let avg7 = SubstanceEngine.rollingAverageMinutes(sessions: saunaSessions, days: 7)
        let avg30 = SubstanceEngine.rollingAverageMinutes(sessions: saunaSessions, days: 30)
        let weeklyCount = SubstanceEngine.weeklySessionCount(sessions: saunaSessions)
        let weeklyMin = SubstanceEngine.weeklyTotalMinutes(sessions: saunaSessions)

        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                substanceStatItem(label: "Today", value: "\(todayMin)m")
                Divider().frame(height: 40)
                substanceStatItem(label: "7d Avg", value: String(format: "%.0fm", avg7))
                Divider().frame(height: 40)
                substanceStatItem(label: "30d Avg", value: String(format: "%.0fm", avg30))
            }
            HStack(spacing: 0) {
                substanceStatItem(label: "This Week", value: "\(weeklyMin)m")
                Divider().frame(height: 40)
                substanceStatItem(label: "Sessions/Wk", value: "\(weeklyCount)")
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

        return DailyBarChartCard(
            title: "Daily Sauna (30 days)",
            data: points,
            barValueLabel: "Minutes",
            yAxisLabel: "minutes",
            color: .orange,
            accessibilityLabel: "Daily sauna duration chart showing minutes over the last 30 days"
        )
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

        let avgHRVSauna = substanceAverage(saunaDays.compactMap(\.nextDayHRV))
        let avgHRVRest = substanceAverage(restDays.compactMap(\.nextDayHRV))
        let avgDeepSauna = substanceAverage(saunaDays.compactMap(\.nextNightDeepPct))
        let avgDeepRest = substanceAverage(restDays.compactMap(\.nextNightDeepPct))
        let avgRemSauna = substanceAverage(saunaDays.compactMap(\.nextNightRemPct))
        let avgRemRest = substanceAverage(restDays.compactMap(\.nextNightRemPct))

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
                let hrvDiff = substancePctDifference(avgHRVRest, avgHRVSauna)
                let deepDiff = substancePctDifference(avgDeepRest, avgDeepSauna)
                let remDiff = substancePctDifference(avgRemRest, avgRemSauna)

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
                            .accessibilityHint("Logs one sauna session. Drag to reorder.")
                            .modifier(ReorderableChip(preset: preset, presets: $saunaPresets) { saved in Task { await DataStore.shared.setSaunaPresets(saved) } })
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
            Text(substanceDisplayDate(session.date))
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
        .modifier(SubstanceRowChrome(
            rowIndex: rowIndex,
            accessibilityLabel: "\(session.saunaType.rawValue) sauna: \(session.temperatureF) degrees Fahrenheit for \(session.durationMinutes) minutes",
            onEdit: { startEditingSauna(session) },
            onDelete: {
                Task {
                    await DataStore.shared.removeSaunaSession(id: session.id)
                    await loadData()
                }
            }
        ))
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

    // MARK: - Actions

    private func quickAddSauna(_ preset: SaunaPreset) async {
        let session = SaunaSession(
            saunaType: preset.saunaType,
            temperatureF: preset.temperatureF,
            durationMinutes: preset.durationMinutes,
            date: substanceTodayString()
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
