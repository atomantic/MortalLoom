import SwiftUI
import Charts

// MARK: - BloodView

struct BloodView: View {
    @State private var bloodTests: [BloodTest] = []
    @State private var sortedTests: [BloodTest] = []
    @State private var correlationData: [CorrelationDataPoint] = []
    @State private var trendAlerts: [BloodTrendEngine.MarkerTrend] = []
    @State private var showingAddForm = false
    @State private var isLoading = true
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }

    private static let trackedMarkers: [(key: String, label: String, color: Color)] = [
        ("ldl", "LDL", .orange),
        ("glucose", "Glucose", .purple),
        ("triglycerides", "Triglycerides", .pink),
        ("hba1c", "HbA1c", .red),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if bloodTests.isEmpty {
                    emptyState
                } else {
                    if !trendAlerts.isEmpty { trendAlertsCard }
                    activityCorrelationChart
                    testList
                }
            }
            .padding()
            .readContainerWidth { containerWidth = $0 }
        }
        .background(Color.bg)
        .proGated()
        .sheet(isPresented: $showingAddForm) {
            BloodTestFormView(onSave: { test in
                Task {
                    await DataStore.shared.addBloodTest(test)
                    await loadData()
                }
            })
        }
        .task { await loadData() }
    }

    private var headerSection: some View {
        HStack {
            Text("Blood Tests (\(bloodTests.count))")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Spacer()
            Button(action: { showingAddForm = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .accessibilityLabel("Add blood test")
        }
        .padding()
        .cardStyle()
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "drop.fill",
            title: "No blood tests recorded.",
            subtitle: "Tap + to add your first test."
        )
        .cardStyle()
    }

    // MARK: - Activity + Blood Marker Correlation

    @ViewBuilder
    private var activityCorrelationChart: some View {
        let availableMarkers = Self.trackedMarkers.filter { marker in
            correlationData.contains { $0.markers[marker.key] != nil }
        }

        if sortedTests.count >= 2 && !correlationData.isEmpty && !availableMarkers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity + Blood Markers")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                Text("30-day avg activity before each test vs. key markers")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        stepsChart(correlationData)
                        markerTrendChart(correlationData, markers: availableMarkers)
                    }
                } else {
                    stepsChart(correlationData)
                    markerTrendChart(correlationData, markers: availableMarkers)
                }

                if correlationData.count >= 2 {
                    activitySummary(correlationData, markers: availableMarkers)
                }
            }
            .padding()
            .cardStyle()
        }
    }

    private func stepsChart(_ data: [CorrelationDataPoint]) -> some View {
        Chart {
            ForEach(data, id: \.testDate) { item in
                BarMark(
                    x: .value("Date", item.testDate),
                    y: .value("Steps", item.avgDailySteps)
                )
                .foregroundStyle(Color.accentColor.opacity(0.3))
            }
        }
        .chartYAxisLabel("Avg Daily Steps")
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
            }
        }
        .frame(height: Layout.chartFrameHeight)
    }

    private func markerTrendChart(_ data: [CorrelationDataPoint], markers: [(key: String, label: String, color: Color)]) -> some View {
        Chart {
            ForEach(markers, id: \.key) { marker in
                ForEach(data, id: \.testDate) { item in
                    if let value = item.markers[marker.key] {
                        LineMark(
                            x: .value("Date", item.testDate),
                            y: .value(marker.label, value),
                            series: .value("Marker", marker.label)
                        )
                        .foregroundStyle(marker.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Date", item.testDate),
                            y: .value(marker.label, value)
                        )
                        .foregroundStyle(marker.color)
                        .symbolSize(30)
                    }
                }
            }
        }
        .chartYAxisLabel("Marker Value")
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
            }
        }
        .frame(height: Layout.chartFrameHeight)
    }

    @ViewBuilder
    private func activitySummary(_ data: [CorrelationDataPoint], markers: [(key: String, label: String, color: Color)]) -> some View {
        if let first = data.first, let last = data.last {
            let stepsDelta = last.avgDailySteps - first.avgDailySteps
            let stepsDir = stepsDelta > 0 ? "higher" : "lower"

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Activity Trend")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                    Text("\(abs(Int(stepsDelta))) steps \(stepsDir)")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(stepsDelta > 0 ? .success : .warning)
                }

                ForEach(markers.prefix(3), id: \.key) { marker in
                    if let firstVal = first.markers[marker.key], let lastVal = last.markers[marker.key] {
                        let delta = lastVal - firstVal
                        let ref = BloodMarkers.byKey[marker.key]
                        let improved = ref.map { delta < 0 && lastVal <= $0.max } ?? (delta < 0)
                        VStack(spacing: 2) {
                            Text(marker.label)
                                .font(.caption2)
                                .foregroundColor(.textMuted)
                            Text("\(delta > 0 ? "+" : "")\(DateFormatting.formatMarkerValue(delta))")
                                .font(.caption).fontWeight(.medium)
                                .foregroundColor(improved ? .success : .warning)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Trend Alerts

    private var trendAlertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.warning)
                Text("Trend Alerts")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
            }

            Text("Markers trending in a concerning direction")
                .font(.caption)
                .foregroundColor(.textSecondary)

            ForEach(trendAlerts) { trend in
                trendAlertRow(trend)
            }
        }
        .padding()
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trend alerts: \(trendAlerts.count) markers need attention")
    }

    private func trendAlertRow(_ trend: BloodTrendEngine.MarkerTrend) -> some View {
        let (icon, color) = trendVisuals(trend)
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(trend.label)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text(trendBadge(trend.severity))
                        .font(.caption2).fontWeight(.medium)
                        .foregroundColor(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.15))
                        .cornerRadius(4)
                }
                Text(trend.detail)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DateFormatting.formatMarkerValue(trend.latestValue))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(color)
                Text("\(trend.changePercent > 0 ? "+" : "")\(String(format: "%.1f", trend.changePercent))%")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
        }
        .padding(8)
        .background(color.opacity(0.05))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trend.detail)
    }

    private func trendVisuals(_ trend: BloodTrendEngine.MarkerTrend) -> (String, Color) {
        switch trend.severity {
        case .worsening:
            return (trend.direction == .rising ? "arrow.up.circle.fill" : "arrow.down.circle.fill", .danger)
        case .approaching:
            return ("exclamationmark.triangle.fill", .warning)
        case .improving:
            return ("arrow.uturn.up.circle.fill", .success)
        case .stable:
            return ("equal.circle.fill", .textMuted)
        }
    }

    private func trendBadge(_ severity: BloodTrendEngine.TrendSeverity) -> String {
        switch severity {
        case .worsening: "Worsening"
        case .approaching: "Watch"
        case .improving: "Improving"
        case .stable: "Stable"
        }
    }

    private var testList: some View {
        ForEach(sortedTests.reversed()) { test in
            BloodTestCardView(test: test, isWide: isWide, onDelete: {
                Task {
                    await DataStore.shared.removeBloodTest(id: test.id)
                    await loadData()
                }
            })
        }
    }

    private func loadData() async {
        let data = await DataStore.shared.getData()
        bloodTests = data.bloodTests
        let sorted = data.bloodTests.sorted { $0.date < $1.date }
        sortedTests = sorted
        correlationData = CorrelationEngine.buildCorrelationData(tests: sorted, healthMetrics: data.healthMetrics)
        trendAlerts = BloodTrendEngine.alerts(tests: sorted)
        isLoading = false
    }
}

// MARK: - Blood Test Card

private struct BloodTestCardView: View {
    let test: BloodTest
    let isWide: Bool
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DateFormatting.displayDate(test.date))
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(test.markers.count) markers")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.danger)
                }
                .accessibilityLabel("Delete blood test from \(DateFormatting.displayDate(test.date))")
            }

            let filledCategories = BloodMarkers.categories.filter { category in
                category.keys.contains(where: { test.markers[$0] != nil })
            }

            ForEach(Array(filledCategories.enumerated()), id: \.offset) { _, category in
                let filledKeys = category.keys.filter { test.markers[$0] != nil }
                if !filledKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.textMuted)
                            .textCase(.uppercase)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: isWide ? 3 : 2), spacing: 6) {
                            ForEach(filledKeys, id: \.self) { key in
                                if let value = test.markers[key],
                                   let ref = BloodMarkers.byKey[key] {
                                    markerCell(ref: ref, value: value)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
        .alert("Delete Test", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this blood test from \(DateFormatting.displayDate(test.date))?")
        }
    }

    private func markerCell(ref: BloodMarkerRef, value: Double) -> some View {
        let status = ref.status(for: value)
        let statusColor: Color = switch status {
        case .normal: .success
        case .low: .warning
        case .high: .danger
        case .unknown: .textMuted
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text(ref.label)
                .font(.caption2)
                .foregroundColor(.textMuted)
                .lineLimit(1)
            HStack(spacing: 2) {
                Text(formatMarkerValue(value))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
                if !ref.unit.isEmpty {
                    Text(ref.unit)
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            }
            Text("\(formatMarkerValue(ref.min))–\(formatMarkerValue(ref.max))")
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.1))
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ref.label): \(formatMarkerValue(value)) \(ref.unit), \(status == .normal ? "normal" : status == .low ? "low" : status == .high ? "high" : "unknown") range \(formatMarkerValue(ref.min)) to \(formatMarkerValue(ref.max))")
    }

    private func formatMarkerValue(_ value: Double) -> String {
        DateFormatting.formatMarkerValue(value)
    }
}

// MARK: - Add Blood Test Form

private struct BloodTestFormView: View {
    let onSave: (BloodTest) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var testDate = Date()
    @State private var markerValues: [String: String] = [:]
    @State private var selectedCategory = 0

    private static let tabLabels = ["Metabolic", "Lipids", "CBC", "Thyroid", "Other"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date + tab picker — always visible above the scroll area
                VStack(spacing: 10) {
                    HStack {
                        Text("Test Date")
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        DatePicker("", selection: $testDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                    .padding(.horizontal)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(Array(Self.tabLabels.enumerated()), id: \.offset) { idx, label in
                            Text(label).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
                .background(Color.bg)

                Divider()

                // Marker list for selected category
                ScrollView {
                    if selectedCategory < BloodMarkers.categories.count {
                        let category = BloodMarkers.categories[selectedCategory]
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(category.keys.enumerated()), id: \.offset) { idx, key in
                                if let ref = BloodMarkers.byKey[key] {
                                    if idx > 0 { Divider().padding(.leading, 16) }
                                    markerRow(ref: ref)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .cardStyle()
                        .padding()
                    }
                }
                .background(Color.bg)
            }
            .background(Color.bg)
            .navigationTitle("Add Blood Test")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTest() }
                        .disabled(parsedMarkers.isEmpty)
                }
            }
        }
    }

    private func markerRow(ref: BloodMarkerRef) -> some View {
        HStack(spacing: 8) {
            Text(ref.label)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
            Spacer(minLength: 8)
            TextField("—", text: binding(for: ref.key))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text(ref.unit.isEmpty ? " " : ref.unit)
                .font(.caption)
                .foregroundColor(.textMuted)
                .frame(width: 44, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { markerValues[key] ?? "" },
            set: { markerValues[key] = $0 }
        )
    }

    private var parsedMarkers: [String: Double] {
        var result: [String: Double] = [:]
        for (key, str) in markerValues {
            if let val = Double(str.trimmingCharacters(in: .whitespaces)), !str.isEmpty {
                result[key] = val
            }
        }
        return result
    }

    private func saveTest() {
        let dateStr = DateFormatting.dateString(testDate)
        let test = BloodTest(date: dateStr, markers: parsedMarkers)
        onSave(test)
        dismiss()
    }
}
