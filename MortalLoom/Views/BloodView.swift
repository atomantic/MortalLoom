import SwiftUI
import Charts

// MARK: - BloodView

struct BloodView: View {
    @State private var bloodTests: [BloodTest] = []
    @State private var healthMetrics: [HealthMetricEntry] = []
    @State private var showingAddForm = false
    @State private var isLoading = true

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
                    activityCorrelationChart
                    testList
                }
            }
            .padding()
        }
        .background(Color.bg)
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
        let sorted = bloodTests.sorted { $0.date < $1.date }
        let correlationData = buildCorrelationData(tests: sorted)
        let trackedMarkers: [(key: String, label: String, color: Color)] = [
            ("ldl", "LDL", .orange),
            ("glucose", "Glucose", .purple),
            ("triglycerides", "Triglycerides", .pink),
            ("hba1c", "HbA1c", .red),
        ]
        let availableMarkers = trackedMarkers.filter { marker in
            correlationData.allSatisfy { $0.markers[marker.key] != nil }
        }

        if sorted.count >= 2 && !correlationData.isEmpty && !availableMarkers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity + Blood Markers")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                Text("30-day avg activity before each test vs. key markers")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                stepsChart(correlationData)
                markerTrendChart(correlationData, markers: availableMarkers)

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
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 120)
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
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 160)
    }

    private struct CorrelationDataPoint {
        let testDate: Date
        let avgDailySteps: Double
        let avgExerciseMin: Double
        let avgActiveEnergy: Double
        let markers: [String: Double]
    }

    private func buildCorrelationData(tests: [BloodTest]) -> [CorrelationDataPoint] {
        let metricsByDate = Dictionary(grouping: healthMetrics, by: \.date)

        return tests.compactMap { test -> CorrelationDataPoint? in
            guard let testDate = DateFormatting.dateFromString(test.date) else { return nil }

            // Get health metrics from 30 days before test
            var totalSteps = 0.0, totalExercise = 0.0, totalEnergy = 0.0, count = 0.0
            for dayOffset in 1...30 {
                guard let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: testDate) else { continue }
                let dayStr = DateFormatting.dateString(day)
                if let metrics = metricsByDate[dayStr]?.first {
                    totalSteps += metrics.steps ?? 0
                    totalExercise += metrics.exerciseMinutes ?? 0
                    totalEnergy += metrics.activeEnergy ?? 0
                    count += 1
                }
            }

            guard count > 0 else { return nil }

            return CorrelationDataPoint(
                testDate: testDate,
                avgDailySteps: totalSteps / count,
                avgExerciseMin: totalExercise / count,
                avgActiveEnergy: totalEnergy / count,
                markers: test.markers
            )
        }
    }

    @ViewBuilder
    private func activitySummary(_ data: [CorrelationDataPoint], markers: [(key: String, label: String, color: Color)]) -> some View {
        let first = data.first!
        let last = data.last!
        let stepsDelta = last.avgDailySteps - first.avgDailySteps
        let stepsDir = stepsDelta > 0 ? "higher" : "lower"

        VStack(alignment: .leading, spacing: 6) {
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

    private var testList: some View {
        ForEach(bloodTests.sorted(by: { $0.date > $1.date })) { test in
            BloodTestCardView(test: test, onDelete: {
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
        healthMetrics = data.healthMetrics
        isLoading = false
    }
}

// MARK: - Blood Test Card

private struct BloodTestCardView: View {
    let test: BloodTest
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

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                        ], spacing: 6) {
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Test Date") {
                    DatePicker("Date", selection: $testDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                ForEach(Array(BloodMarkers.categories.enumerated()), id: \.offset) { _, category in
                    Section(category.name) {
                        ForEach(category.keys, id: \.self) { key in
                            if let ref = BloodMarkers.byKey[key] {
                                HStack {
                                    Text(ref.label)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    TextField("—", text: binding(for: key))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                    if !ref.unit.isEmpty {
                                        Text(ref.unit)
                                            .font(.caption)
                                            .foregroundColor(.textMuted)
                                            .frame(width: 50, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }
            }
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
