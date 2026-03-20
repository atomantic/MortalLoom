import SwiftUI
import Charts
import HealthKit

// MARK: - Weight Data Point

private struct WeightPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - BodyView

struct BodyView: View {
    @State private var eyeExams: [EyeExam] = []
    @State private var sortedEyeExams: [EyeExam] = []
    @State private var showingAddExam = false
    @State private var editingExam: EyeExam?
    @State private var isLoading = true

    // Body composition
    @State private var weightPoints: [WeightPoint] = []
    @State private var latestWeight: Double?
    @State private var latestBodyFat: Double?
    @State private var latestLeanMass: Double?
    @State private var weightDate: Date?
    @State private var bodyFatDate: Date?

    // Manual entry
    @State private var showingManualEntry = false
    @State private var manualWeight = ""
    @State private var manualBodyFat = ""

    @StateObject private var healthKit = HealthKitService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                bodyCompositionSection
                eyePrescriptionSection
            }
            .padding()
        }
        .background(Color.bg)
        .sheet(isPresented: $showingAddExam) {
            EyeExamFormView(onSave: { exam in
                Task {
                    await DataStore.shared.addEyeExam(exam)
                    await loadData()
                }
            })
        }
        .sheet(item: $editingExam) { exam in
            EyeExamFormView(existing: exam, onSave: { updated in
                Task {
                    await DataStore.shared.updateEyeExam(updated)
                    await loadData()
                }
            })
        }
        .task {
            await healthKit.requestAuthorization()
            await loadData()
            await loadHealthKitData()
        }
    }

    // MARK: - Body Composition Section

    private var bodyCompositionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Body Composition")
                .font(.headline)
                .foregroundColor(.textPrimary)

            // Weight chart
            if !weightPoints.isEmpty {
                Chart(weightPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(20)
                }
                .chartYAxisLabel("lbs")
                .frame(height: Layout.chartFrameHeight)
                .padding(.vertical, 4)
            } else {
                Text("No weight data available")
                    .font(.subheadline)
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }

            // Latest values
            HStack(spacing: 16) {
                statCard(label: "Weight", value: latestWeight.map { String(format: "%.1f lbs", $0) } ?? "—", date: weightDate)
                statCard(label: "Body Fat", value: latestBodyFat.map { String(format: "%.1f%%", $0) } ?? "—", date: bodyFatDate)
                statCard(label: "Lean Mass", value: latestLeanMass.map { String(format: "%.1f lbs", $0) } ?? "—", date: nil)
            }

            // Manual entry toggle
            Button(action: { showingManualEntry.toggle() }) {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text(showingManualEntry ? "Hide Manual Entry" : "Add Manual Entry")
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }

            if showingManualEntry {
                manualEntryForm
            }
        }
        .padding()
        .cardStyle()
    }

    private func statCard(label: String, value: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.textMuted)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)
            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var manualEntryForm: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Weight (lbs)")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Spacer()
                TextField("0.0", text: $manualWeight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            HStack {
                Text("Body Fat %")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Spacer()
                TextField("optional", text: $manualBodyFat)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            Button(action: saveManualEntry) {
                Text("Save Entry")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .disabled(Double(manualWeight) == nil)
        }
        .padding(12)
        .background(Color.bgInput)
        .cornerRadius(8)
    }

    // MARK: - Eye Prescriptions Section

    private var eyePrescriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Eye Prescriptions (\(eyeExams.count))")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: { showingAddExam = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }

            if eyeExams.isEmpty {
                EmptyStateView(
                    icon: "eye",
                    title: "No eye exams recorded yet.",
                    subtitle: "Tap + to add your first exam."
                )
            } else {
                eyeExamTable
            }
        }
        .padding()
        .cardStyle()
    }

    private var eyeExamTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("Date")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    Text("L SPH")
                    Text("L CYL")
                    Text("L AXIS")
                    Text("R SPH")
                    Text("R CYL")
                    Text("R AXIS")
                }
                .frame(width: 56, alignment: .trailing)
            }
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.textMuted)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ForEach(sortedEyeExams) { exam in
                HStack(spacing: 0) {
                    Text(DateFormatting.displayDate(exam.date))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        Text(formatSphere(exam.leftSphere))
                        Text(formatSphere(exam.leftCylinder))
                        Text(formatAxis(exam.leftAxis))
                        Text(formatSphere(exam.rightSphere))
                        Text(formatSphere(exam.rightCylinder))
                        Text(formatAxis(exam.rightAxis))
                    }
                    .frame(width: 56, alignment: .trailing)
                }
                .font(.caption)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contextMenu {
                    Button(action: { editingExam = exam }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: {
                        Task {
                            await DataStore.shared.removeEyeExam(id: exam.id)
                            await loadData()
                        }
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                }

                if exam.id != sortedEyeExams.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Formatting

    private func formatSphere(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.2f", value)
    }

    private func formatAxis(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)\u{00B0}"
    }

    // MARK: - Data Loading

    private func loadData() async {
        let data = await DataStore.shared.getData()
        eyeExams = data.eyeExams
        sortedEyeExams = data.eyeExams.sorted(by: { $0.date > $1.date })
        isLoading = false
    }

    private func loadHealthKitData() async {
        // Weight history for chart (last 90 days)
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -90, to: end) ?? end

        // Run all HealthKit queries in parallel
        async let weightData = healthKit.dailyStats(
            for: .bodyMass,
            unit: .pound(),
            aggregation: .average,
            from: start,
            to: end
        )
        async let latestWeightResult = healthKit.latestValue(for: .bodyMass, unit: .pound())
        async let latestFatResult = healthKit.latestValue(for: .bodyFatPercentage, unit: .percent())
        async let latestLeanResult = healthKit.latestValue(for: .leanBodyMass, unit: .pound())

        let (wd, lw, lf, ll) = await (weightData, latestWeightResult, latestFatResult, latestLeanResult)

        weightPoints = wd.map { WeightPoint(date: $0.date, value: $0.value) }

        if let w = lw {
            latestWeight = w.value
            weightDate = w.date
        }
        if let bf = lf {
            latestBodyFat = bf.value * 100
            bodyFatDate = bf.date
        }
        if let lm = ll {
            latestLeanMass = lm.value
        }

        // If HealthKit has no weight data but we have manual, compute lean mass
        if latestLeanMass == nil, let w = latestWeight, let bf = latestBodyFat {
            latestLeanMass = w * (1 - bf / 100)
        }
    }

    private func saveManualEntry() {
        guard let weight = Double(manualWeight) else { return }
        let date = Date()
        let dateStr = DateFormatting.dateString(date)
        let bf = Double(manualBodyFat)

        // Update local state immediately
        let point = WeightPoint(date: date, value: weight)
        weightPoints.append(point)
        latestWeight = weight
        weightDate = date

        if let bf {
            latestBodyFat = bf
            bodyFatDate = date
            latestLeanMass = weight * (1 - bf / 100)
        }

        // Persist to DataStore
        let entry = BodyEntry(date: dateStr, weightLbs: weight, bodyFatPct: bf)
        Task { await DataStore.shared.addBodyEntry(entry) }

        manualWeight = ""
        manualBodyFat = ""
        showingManualEntry = false
    }
}

// MARK: - Eye Exam Form

private struct EyeExamFormView: View {
    let existing: EyeExam?
    let onSave: (EyeExam) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var examDate: Date
    @State private var leftSphere: String
    @State private var leftCylinder: String
    @State private var leftAxis: String
    @State private var rightSphere: String
    @State private var rightCylinder: String
    @State private var rightAxis: String

    init(existing: EyeExam? = nil, onSave: @escaping (EyeExam) -> Void) {
        self.existing = existing
        self.onSave = onSave

        let date: Date
        if let existing, let d = DateFormatting.dateFromString( existing.date) {
            date = d
        } else {
            date = Date()
        }

        _examDate = State(initialValue: date)
        _leftSphere = State(initialValue: existing?.leftSphere.map { String(format: "%.2f", $0) } ?? "")
        _leftCylinder = State(initialValue: existing?.leftCylinder.map { String(format: "%.2f", $0) } ?? "")
        _leftAxis = State(initialValue: existing?.leftAxis.map { String($0) } ?? "")
        _rightSphere = State(initialValue: existing?.rightSphere.map { String(format: "%.2f", $0) } ?? "")
        _rightCylinder = State(initialValue: existing?.rightCylinder.map { String(format: "%.2f", $0) } ?? "")
        _rightAxis = State(initialValue: existing?.rightAxis.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exam Date") {
                    DatePicker("Date", selection: $examDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                Section("Left Eye (OS)") {
                    fieldRow("SPH (Sphere)", text: $leftSphere)
                    fieldRow("CYL (Cylinder)", text: $leftCylinder)
                    fieldRow("AXIS", text: $leftAxis, isAxis: true)
                }

                Section("Right Eye (OD)") {
                    fieldRow("SPH (Sphere)", text: $rightSphere)
                    fieldRow("CYL (Cylinder)", text: $rightCylinder)
                    fieldRow("AXIS", text: $rightAxis, isAxis: true)
                }
            }
            .navigationTitle(existing == nil ? "Add Eye Exam" : "Edit Eye Exam")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveExam() }
                }
            }
        }
    }

    private func fieldRow(_ label: String, text: Binding<String>, isAxis: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.textPrimary)
            Spacer()
            TextField("—", text: text)
                .keyboardType(isAxis ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func saveExam() {
        let dateStr = DateFormatting.dateString( examDate)
        let exam = EyeExam(
            id: existing?.id ?? UUID(),
            date: dateStr,
            leftSphere: Double(leftSphere),
            leftCylinder: Double(leftCylinder),
            leftAxis: Int(leftAxis),
            rightSphere: Double(rightSphere),
            rightCylinder: Double(rightCylinder),
            rightAxis: Int(rightAxis)
        )
        onSave(exam)
        dismiss()
    }
}
