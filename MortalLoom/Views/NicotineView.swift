import SwiftUI
import Charts

// MARK: - NicotineView

/// Nicotine tracker tab: quick-add, stats, consumption + heart-rate correlation
/// charts, custom logging, and history. Owns only nicotine state.
struct NicotineView: View {
    @State private var nicotineEntries: [NicotineEntry] = []
    @State private var nicotinePresets: [NicotinePreset] = []

    // Health metrics for correlation charts
    @State private var healthMetrics: [HealthMetricEntry] = []

    // Form
    @State private var nicoProduct = ""
    @State private var nicoMgPerUnit = ""
    @State private var nicoCount = "1"
    @State private var nicoDate = Date()

    // Edit sheet
    @State private var editingNicotine: NicotineEntry?
    @State private var showDeleteConfirm = false
    @State private var showNicotinePresetManager = false

    @State private var toastMessage: String?

    // Edit form state
    @State private var editNicoProduct = ""
    @State private var editNicoMg = ""
    @State private var editNicoCount = ""
    @State private var editNicoDate = ""

    var body: some View {
        VStack(spacing: 16) {
            nicotineQuickAdd
            nicotineStatsBar
            nicotineChart
            nicotineHeartRateCorrelation
            nicotineCustomForm
            nicotineHistory
        }
        .padding()
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
        .sheet(item: $editingNicotine) { entry in
            nicotineEditSheet(entry)
        }
        .sheet(isPresented: $showNicotinePresetManager) {
            NicotinePresetManagerView(presets: $nicotinePresets, onSave: { newPresets in
                Task { await DataStore.shared.setNicotinePresets(newPresets) }
            })
        }
        .toast($toastMessage)
    }

    // MARK: - Data Loading

    private func loadData() async {
        let data = await DataStore.shared.getData()
        nicotineEntries = data.nicotineEntries
        nicotinePresets = data.nicotinePresets
        healthMetrics = data.healthMetrics
    }

    // MARK: Nicotine Stats

    private var nicotineStatsBar: some View {
        let today = substanceTodayString()
        let todayMg = nicotineEntries.filter { $0.date == today }.reduce(0.0) { $0 + $1.totalMg }
        let avg7 = SubstanceEngine.rollingAverageMg(entries: nicotineEntries, days: 7)
        let avg30 = SubstanceEngine.rollingAverageMg(entries: nicotineEntries, days: 30)
        let weeklyTotal = SubstanceEngine.weeklyTotalMg(entries: nicotineEntries)
        let allTimeAvg = SubstanceEngine.allTimeAverageMg(entries: nicotineEntries)

        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                substanceStatItem(label: "Today", value: String(format: "%.1fmg", todayMg))
                Divider().frame(height: 40)
                substanceStatItem(label: "7d Avg", value: String(format: "%.1fmg", avg7))
                Divider().frame(height: 40)
                substanceStatItem(label: "30d Avg", value: String(format: "%.1fmg", avg30))
            }

            HStack(spacing: 0) {
                substanceStatItem(label: "Weekly", value: String(format: "%.1fmg", weeklyTotal))
                Divider().frame(height: 40)
                substanceStatItem(label: "All-time Avg", value: String(format: "%.1fmg", allTimeAvg))
                Divider().frame(height: 40)
                substanceStatItem(label: "", value: "")  // Placeholder for symmetry
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

        return DailyBarChartCard(
            title: "Daily Nicotine (30 days)",
            data: dailyData,
            barValueLabel: "mg",
            yAxisLabel: "mg",
            color: .warning,
            accessibilityLabel: "Daily nicotine consumption chart showing milligrams over the last 30 days"
        )
    }

    // MARK: Nicotine + Heart Rate Correlation

    @ViewBuilder
    private var nicotineHeartRateCorrelation: some View {
        let model = CorrelationEngine.nicotineHeartRateCorrelation(
            entries: nicotineEntries,
            healthMetrics: healthMetrics
        )
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
        QuickAddPresetRow(
            presets: $nicotinePresets,
            accessibilityHint: { "Logs one \($0.name) nicotine entry. Drag to reorder." },
            onAdd: { preset in Task { await quickAddNicotine(preset) } },
            onManage: { showNicotinePresetManager = true },
            persist: { saved in Task { await DataStore.shared.setNicotinePresets(saved) } }
        )
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
            Text(substanceDisplayDate(entry.date))
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
        .modifier(SubstanceRowChrome(
            rowIndex: rowIndex,
            accessibilityLabel: "\(entry.product): \(String(format: "%.1f", entry.totalMg)) milligrams total, \(String(format: "%.1f", entry.mgPerUnit)) mg per unit, \(entry.count) units",
            onEdit: { startEditingNicotine(entry) },
            onDelete: {
                Task {
                    await DataStore.shared.removeNicotineEntry(id: entry.id)
                    await loadData()
                }
            }
        ))
    }

    // MARK: Nicotine Edit Sheet

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

    private func quickAddNicotine(_ preset: NicotinePreset) async {
        let today = substanceTodayString()
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
            date: DateFormatting.dateString(nicoDate)
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
