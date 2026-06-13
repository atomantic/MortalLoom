import SwiftUI
import Charts
import HealthKit

// MARK: - Weight Data Point

private struct WeightPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - Cardio Data Point

private struct CardioPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - Blood Pressure Data Point

private struct BPPoint: Identifiable {
    let id = UUID()
    let date: Date
    let systolic: Double
    let diastolic: Double
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

    // Cardio fitness
    @State private var latestVO2Max: Double?
    @State private var vo2MaxDate: Date?
    @State private var vo2MaxHistory: [CardioPoint] = []
    @State private var latestRestingHR: Double?
    @State private var restingHRDate: Date?
    @State private var latestHRV: Double?
    @State private var hrvDate: Date?
    @State private var userAge: Int = 0
    @State private var userSex: BiologicalSex?

    // Cardio recovery
    @State private var latestCardioRecovery: Double?
    @State private var cardioRecoveryDate: Date?

    // Blood pressure
    @State private var bpHistory: [BPPoint] = []
    @State private var showingBPEntry = false
    @State private var manualBPSystolic = ""
    @State private var manualBPDiastolic = ""

    // Gait & activity
    @State private var gaitSummary: GaitEngine.GaitSummary?
    @State private var latestDaylightMinutes: Double?
    @State private var latestStandMinutes: Double?
    @State private var latestBasalEnergy: Double?

    // Manual entry
    @State private var showingManualEntry = false
    @State private var manualWeight = ""
    @State private var manualBodyFat = ""

    @State private var healthKit = HealthKitService.shared
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        bodyCompositionSection
                            .frame(maxWidth: .infinity)
                        cardioFitnessSection
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    bodyCompositionSection
                    cardioFitnessSection
                }
                bloodPressureSection
                gaitSection
                activitySection
                eyePrescriptionSection.proGated()
            }
            .padding()
            .readContainerWidth { containerWidth = $0 }
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
            }, onDelete: {
                Task {
                    await DataStore.shared.removeEyeExam(id: exam.id)
                    await loadData()
                }
            })
        }
        .task {
            await healthKit.requestAuthorization()
            await loadData()
            await loadHealthKitData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadHealthKitData() }
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
                    if weightPoints.count <= 90 {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(20)
                    }
                }
                .chartYAxisLabel("lbs")
                .frame(height: Layout.chartFrameHeight)
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weight trend chart showing \(weightPoints.count) data points over time in pounds")
            } else {
                Text("No weight data available")
                    .font(.subheadline)
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }

            // Latest values
            HStack(spacing: 16) {
                StatCell(label: "Weight", value: latestWeight.map { String(format: "%.1f lbs", $0) } ?? "—", date: weightDate)
                StatCell(label: "Body Fat", value: latestBodyFat.map { String(format: "%.1f%%", $0) } ?? "—", date: bodyFatDate)
                StatCell(label: "Lean Mass", value: latestLeanMass.map { String(format: "%.1f lbs", $0) } ?? "—")
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
            .accessibilityLabel(showingManualEntry ? "Hide manual weight entry form" : "Show manual weight entry form")

            if showingManualEntry {
                manualEntryForm
            }
        }
        .padding()
        .cardStyle()
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
                    .accessibilityLabel("Weight in pounds")
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
                    .accessibilityLabel("Body fat percentage, optional")
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

    // MARK: - Cardio Fitness Section

    @ViewBuilder
    private var cardioFitnessSection: some View {
        if latestVO2Max != nil || latestRestingHR != nil || latestHRV != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Cardio Fitness")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    CitationBadge(
                        ids: [
                            CitationLibrary.acsmGuidelines.id,
                            CitationLibrary.coleHrr1999.id,
                            CitationLibrary.kodamaFitness2009.id,
                        ],
                        claim: "VO2 Max thresholds, HR Recovery classification, and longevity impact"
                    )
                    Spacer()
                }

                // VO2 Max chart
                if !vo2MaxHistory.isEmpty {
                    Chart(vo2MaxHistory) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("VO2 Max", point.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("VO2 Max", point.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(20)
                    }
                    .chartYAxisLabel("mL/kg/min")
                    .frame(height: Layout.chartFrameHeight)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("VO2 Max trend chart showing \(vo2MaxHistory.count) readings over time")
                }

                // Metric cards
                HStack(spacing: 12) {
                    if let vo2 = latestVO2Max {
                        cardioMetricCard(
                            label: "VO2 Max",
                            value: String(format: "%.1f", vo2),
                            unit: "mL/kg/min",
                            date: vo2MaxDate,
                            classification: CardioFitnessEngine.classifyVO2Max(vo2, age: userAge, sex: userSex).rawValue,
                            classificationColor: CardioFitnessEngine.classifyVO2Max(vo2, age: userAge, sex: userSex).color.semanticColor,
                            icon: CardioFitnessEngine.classifyVO2Max(vo2, age: userAge, sex: userSex).systemImage
                        )
                    }
                    if let rhr = latestRestingHR {
                        let zone = CardioFitnessEngine.classifyRestingHR(rhr)
                        cardioMetricCard(
                            label: "Resting HR",
                            value: String(format: "%.0f", rhr),
                            unit: "bpm",
                            date: restingHRDate,
                            classification: zone.rawValue,
                            classificationColor: zone.color.semanticColor,
                            icon: "heart.fill"
                        )
                    }
                    if let hrv = latestHRV {
                        let level = CardioFitnessEngine.classifyHRV(hrv, age: userAge)
                        cardioMetricCard(
                            label: "HRV",
                            value: String(format: "%.0f", hrv),
                            unit: "ms",
                            date: hrvDate,
                            classification: level.rawValue,
                            classificationColor: level.color.semanticColor,
                            icon: "waveform.path.ecg"
                        )
                    }
                }

                // HR Recovery card
                if let rec = latestCardioRecovery {
                    let level = CardioFitnessEngine.classifyRecovery(rec)
                    cardioMetricCard(
                        label: "HR Recovery",
                        value: String(format: "%.0f", rec),
                        unit: "bpm drop/1min",
                        date: cardioRecoveryDate,
                        classification: level.rawValue,
                        classificationColor: level.color.semanticColor,
                        icon: level.systemImage
                    )
                }

                // Longevity impact
                if let vo2 = latestVO2Max {
                    let impact = CardioFitnessEngine.vo2MaxLongevityImpact(vo2, age: userAge, sex: userSex)
                    HStack(spacing: 6) {
                        Image(systemName: impact >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundColor(impact >= 0 ? .success : .danger)
                            .font(.caption)
                        Text("VO2 Max fitness level: \(impact >= 0 ? "+" : "")\(String(format: "%.1f", impact)) years estimated life expectancy impact")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("VO2 Max fitness impact: \(impact >= 0 ? "plus" : "minus") \(String(format: "%.1f", abs(impact))) years on life expectancy")
                }

                if let rec = latestCardioRecovery {
                    let recImpact = CardioFitnessEngine.recoveryLongevityImpact(rec)
                    HStack(spacing: 6) {
                        Image(systemName: recImpact >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundColor(recImpact >= 0 ? .success : .danger)
                            .font(.caption)
                        Text("HR recovery \(String(format: "%.0f", rec)) bpm: \(recImpact >= 0 ? "+" : "")\(String(format: "%.1f", recImpact)) years estimated life expectancy impact")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding()
            .cardStyle()
        }
    }

    /// Leading-aligned metric card: an icon+label header, a bold value, and
    /// optional unit / classification / date lines. The icon and classification
    /// share `classificationColor`; `valueColor` tints the value independently.
    /// Used for cardio readings as well as the gait, mobility, and activity metrics.
    /// `accessibilityLabel` overrides the default value+unit spoken label — pass a
    /// fully spelled-out string when the abbreviated unit reads poorly via VoiceOver.
    private func cardioMetricCard(label: String, value: String, unit: String? = nil, date: Date? = nil, classification: String? = nil, classificationColor: Color, icon: String, valueColor: Color = .textPrimary, accessibilityLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(classificationColor)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(valueColor)
            if let unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            if let classification {
                Text(classification)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(classificationColor)
            }
            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? "\(label): \(value)\(unit.map { " \($0)" } ?? "")\(classification.map { ", \($0)" } ?? "")")
    }

    // MARK: - Blood Pressure Section

    private var bloodPressureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Blood Pressure")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: { showingBPEntry.toggle() }) {
                    Image(systemName: showingBPEntry ? "minus.circle.fill" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .accessibilityLabel(showingBPEntry ? "Hide blood pressure entry" : "Add blood pressure reading")
            }

            if !bpHistory.isEmpty {
                Chart(bpHistory) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Systolic", point.systolic)
                    )
                    .foregroundStyle(Color.danger)
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Diastolic", point.diastolic)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
                    if bpHistory.count <= 90 {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Systolic", point.systolic)
                        )
                        .foregroundStyle(Color.danger)
                        .symbolSize(20)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Diastolic", point.diastolic)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(20)
                    }
                }
                .chartYAxisLabel("mmHg")
                .frame(height: Layout.chartFrameHeight)
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Blood pressure trend chart showing \(bpHistory.count) readings")
            }

            if let latest = bpHistory.last {
                let category = CardioFitnessEngine.classifyBP(systolic: latest.systolic, diastolic: latest.diastolic)
                cardioMetricCard(
                    label: "Latest Reading",
                    value: "\(Int(latest.systolic))/\(Int(latest.diastolic))",
                    unit: "mmHg",
                    date: latest.date,
                    classification: category.rawValue,
                    classificationColor: category.color.semanticColor,
                    icon: category.systemImage
                )

                let impact = CardioFitnessEngine.bpLongevityImpact(systolic: latest.systolic, diastolic: latest.diastolic)
                HStack(spacing: 6) {
                    Image(systemName: impact >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(impact >= 0 ? .success : .danger)
                        .font(.caption)
                    Text("Blood pressure \(Int(latest.systolic))/\(Int(latest.diastolic)): \(impact >= 0 ? "+" : "")\(String(format: "%.1f", impact)) years estimated life expectancy impact")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }

            if bpHistory.isEmpty && !showingBPEntry {
                EmptyStateView(
                    icon: "heart.text.clipboard",
                    title: "No blood pressure data yet.",
                    subtitle: "Tap + to enter a reading or sync from Apple Health."
                )
            }

            if showingBPEntry {
                bpEntryForm
            }
        }
        .padding()
        .cardStyle()
    }

    private var bpEntryForm: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Systolic (top)")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Spacer()
                TextField("120", text: $manualBPSystolic)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityLabel("Systolic pressure")
            }
            HStack {
                Text("Diastolic (bottom)")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Spacer()
                TextField("80", text: $manualBPDiastolic)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityLabel("Diastolic pressure")
            }
            Button(action: saveBPEntry) {
                Text("Save Reading")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .disabled(Double(manualBPSystolic) == nil || Double(manualBPDiastolic) == nil)
        }
        .padding(12)
        .background(Color.bgInput)
        .cornerRadius(8)
    }

    // MARK: - Gait & Mobility Section

    @ViewBuilder
    private var gaitSection: some View {
        if let gait = gaitSummary, (gait.avgWalkingSpeed != nil || gait.avgWalkingDistance != nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Gait & Mobility")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    CitationBadge(
                        ids: [
                            CitationLibrary.studenskiGait2011.id,
                            CitationLibrary.hausdorffFalls2001.id,
                        ],
                        claim: "Walking speed as a predictor of mortality; gait variability and fall risk"
                    )
                    Spacer()
                }

                HStack(spacing: 12) {
                    if let speed = gait.avgWalkingSpeed, let level = gait.speedLevel {
                        cardioMetricCard(
                            label: "Walk Speed",
                            value: String(format: "%.2f", speed),
                            unit: "m/s",
                            classification: level.rawValue,
                            classificationColor: level.color.semanticColor,
                            icon: level.systemImage,
                            accessibilityLabel: "Walking speed: \(String(format: "%.2f", speed)) meters per second, \(level.rawValue)"
                        )
                    }

                    if let dist = gait.avgWalkingDistance {
                        cardioMetricCard(
                            label: "Daily Distance",
                            value: String(format: "%.1f", dist),
                            unit: "km avg",
                            classificationColor: .accentColor,
                            icon: "figure.walk",
                            accessibilityLabel: "Daily walking distance: \(String(format: "%.1f", dist)) kilometers average"
                        )
                    }

                    cardioMetricCard(
                        label: "Fall Risk",
                        value: gait.fallRisk.rawValue,
                        unit: gait.avgAsymmetry.map { String(format: "%.1f%% asym", $0) },
                        classificationColor: gait.fallRisk.color.semanticColor,
                        icon: "exclamationmark.shield",
                        valueColor: gait.fallRisk.color.semanticColor,
                        accessibilityLabel: "Fall risk: \(gait.fallRisk.rawValue)\(gait.avgAsymmetry.map { String(format: ", %.1f percent asymmetry", $0) } ?? "")"
                    )
                }

                // Longevity impact
                if let years = gait.longevityYears {
                    HStack(spacing: 6) {
                        Image(systemName: years >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundColor(years >= 0 ? .success : .danger)
                            .font(.caption)
                        Text("Walking speed: \(years >= 0 ? "+" : "")\(String(format: "%.1f", years)) years estimated life expectancy impact")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }

                    Text("Source: Studenski et al., JAMA 2011 — walking speed as predictor of survival")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            }
            .padding()
            .cardStyle()
        }
    }

    // MARK: - Activity Metrics Section

    @ViewBuilder
    private var activitySection: some View {
        if latestStandMinutes != nil || latestBasalEnergy != nil || latestDaylightMinutes != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity & Environment")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                HStack(spacing: 12) {
                    if let stand = latestStandMinutes {
                        cardioMetricCard(
                            label: "Stand Time",
                            value: String(format: "%.0f", stand),
                            unit: "min/day avg",
                            classificationColor: .accentColor,
                            icon: "figure.stand",
                            accessibilityLabel: "Stand time: \(String(format: "%.0f", stand)) minutes per day average"
                        )
                    }

                    if let basal = latestBasalEnergy {
                        cardioMetricCard(
                            label: "Basal Energy",
                            value: String(format: "%.0f", basal),
                            unit: "kcal/day",
                            classificationColor: .orange,
                            icon: "flame",
                            accessibilityLabel: "Basal energy: \(String(format: "%.0f", basal)) kilocalories per day"
                        )
                    }

                    if let daylight = latestDaylightMinutes {
                        cardioMetricCard(
                            label: "Daylight",
                            value: String(format: "%.0f", daylight),
                            unit: "min/day avg",
                            classificationColor: .yellow,
                            icon: "sun.max.fill",
                            valueColor: daylight >= 30 ? .success : .warning,
                            accessibilityLabel: "Daylight exposure: \(String(format: "%.0f", daylight)) minutes per day average, \(daylight >= 30 ? "meeting" : "below") recommended 30 minutes"
                        )
                    }
                }

                if latestDaylightMinutes != nil {
                    Text("Aim for 30+ minutes of outdoor daylight daily for circadian regulation, vitamin D synthesis, and mood support.")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            }
            .padding()
            .cardStyle()
        }
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
                .accessibilityLabel("Add eye exam")
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
            ForEach(sortedEyeExams) { exam in
                eyeExamRow(exam)
                if exam.id != sortedEyeExams.last?.id {
                    Divider()
                }
            }
        }
    }

    private func eyeExamRow(_ exam: EyeExam) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DateFormatting.displayDate(exam.date))
                .font(.caption.bold())
                .foregroundColor(.textPrimary)

            HStack(spacing: 8) {
                eyeExamEyeBlock(
                    label: "L",
                    sph: exam.leftSphere,
                    cyl: exam.leftCylinder,
                    axis: exam.leftAxis
                )
                eyeExamEyeBlock(
                    label: "R",
                    sph: exam.rightSphere,
                    cyl: exam.rightCylinder,
                    axis: exam.rightAxis
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { editingExam = exam }
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
    }

    private func eyeExamEyeBlock(label: String, sph: Double?, cyl: Double?, axis: Int?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(.accentColor)
                .frame(width: 12, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                eyeExamMetricLine(name: "SPH", value: formatSphere(sph))
                eyeExamMetricLine(name: "CYL", value: formatSphere(cyl))
                eyeExamMetricLine(name: "AXIS", value: formatAxis(axis))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eyeExamMetricLine(name: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption2)
                .foregroundColor(.textMuted)
            Spacer(minLength: 2)
            Text(value)
                .font(.caption)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
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
        userSex = data.profile.biologicalSex
        if let birthStr = data.profile.birthDate,
           let birthDate = DateFormatting.dateFromString(birthStr) {
            userAge = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        }
        isLoading = false
    }

    private func loadHealthKitData() async {
        // Weight history for chart (last 365 days)
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -365, to: end) ?? end

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

        // Cardio fitness queries
        async let vo2Result = healthKit.latestValue(for: .vo2Max, unit: HKUnit(from: "ml/kg*min"))
        async let rhrResult = healthKit.latestValue(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrvResult = healthKit.latestValue(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let vo2History = healthKit.dailyStats(
            for: .vo2Max,
            unit: HKUnit(from: "ml/kg*min"),
            aggregation: .average,
            from: start,
            to: end
        )

        let (wd, lw, lf, ll, vo2, rhr, hrv, vo2h) = await (weightData, latestWeightResult, latestFatResult, latestLeanResult, vo2Result, rhrResult, hrvResult, vo2History)

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

        // Fall back to DataStore body entries when HealthKit is unavailable (macOS) or returns no data
        let data = await DataStore.shared.getData()
        if latestWeight == nil || weightPoints.isEmpty {
            let sortedEntries = data.bodyEntries.sorted { $0.date > $1.date }
            if latestWeight == nil, let latest = sortedEntries.first(where: { $0.weightLbs != nil }) {
                latestWeight = latest.weightLbs
                weightDate = DateFormatting.dateFromString(latest.date)
            }
            if latestBodyFat == nil, let latest = sortedEntries.first(where: { $0.bodyFatPct != nil }) {
                latestBodyFat = latest.bodyFatPct
                bodyFatDate = DateFormatting.dateFromString(latest.date)
            }
            if weightPoints.isEmpty {
                weightPoints = sortedEntries.compactMap { entry -> WeightPoint? in
                    guard let w = entry.weightLbs, let d = DateFormatting.dateFromString(entry.date) else { return nil }
                    return WeightPoint(date: d, value: w)
                }
            }
        }

        if weightPoints.isEmpty, let w = latestWeight, let d = weightDate {
            weightPoints = [WeightPoint(date: d, value: w)]
        }

        if latestLeanMass == nil, let w = latestWeight, let bf = latestBodyFat {
            latestLeanMass = w * (1 - bf / 100)
        }

        // Cardio fitness
        if let v = vo2 {
            latestVO2Max = v.value
            vo2MaxDate = v.date
        }
        if let r = rhr {
            latestRestingHR = r.value
            restingHRDate = r.date
        }
        if let h = hrv {
            latestHRV = h.value
            hrvDate = h.date
        }
        vo2MaxHistory = vo2h.map { CardioPoint(date: $0.date, value: $0.value) }

        // Cardio recovery
        if let rec = await healthKit.latestValue(for: .heartRateRecoveryOneMinute, unit: .count().unitDivided(by: .minute())) {
            latestCardioRecovery = rec.value
            cardioRecoveryDate = rec.date
        }

        // Blood pressure & gait/activity from stored health metrics
        let metricsByDateDesc = data.healthMetrics.sorted { $0.date > $1.date }
        bpHistory = metricsByDateDesc.reversed().compactMap { m -> BPPoint? in
            guard let sys = m.bloodPressureSystolic,
                  let dia = m.bloodPressureDiastolic,
                  let d = DateFormatting.dateFromString(m.date) else { return nil }
            return BPPoint(date: d, systolic: sys, diastolic: dia)
        }

        let recentMetrics = metricsByDateDesc.prefix(30)
        gaitSummary = GaitEngine.summarize(metrics: Array(recentMetrics), age: userAge)

        // Latest averages for activity section
        latestStandMinutes = recentMetrics.compactAverage(\.standMinutes)
        latestBasalEnergy = recentMetrics.compactAverage(\.basalEnergy)
        latestDaylightMinutes = recentMetrics.compactAverage(\.daylightMinutes)
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

    private func saveBPEntry() {
        guard let sys = Double(manualBPSystolic),
              let dia = Double(manualBPDiastolic) else { return }
        let date = Date()
        let dateStr = DateFormatting.dateString(date)

        let newPoint = BPPoint(date: date, systolic: sys, diastolic: dia)
        if let idx = bpHistory.firstIndex(where: { $0.date > date }) {
            bpHistory.insert(newPoint, at: idx)
        } else {
            bpHistory.append(newPoint)
        }

        let entry = HealthMetricEntry(
            date: dateStr,
            bloodPressureSystolic: sys,
            bloodPressureDiastolic: dia
        )
        Task { await DataStore.shared.upsertHealthMetric(entry) }

        manualBPSystolic = ""
        manualBPDiastolic = ""
        showingBPEntry = false
    }
}

// MARK: - Eye Exam Form

private struct EyeExamFormView: View {
    let existing: EyeExam?
    let onSave: (EyeExam) -> Void
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var examDate: Date
    @State private var leftSphere: String
    @State private var leftCylinder: String
    @State private var leftAxis: String
    @State private var rightSphere: String
    @State private var rightCylinder: String
    @State private var rightAxis: String
    @State private var showDeleteConfirm = false
    @FocusState private var focusedField: EyeField?

    enum EyeField {
        case leftSphere, leftCylinder, rightSphere, rightCylinder, leftAxis, rightAxis
        var isSigned: Bool {
            switch self {
            case .leftAxis, .rightAxis: false
            default: true
            }
        }
    }

    init(existing: EyeExam? = nil, onSave: @escaping (EyeExam) -> Void, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete

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
                    fieldRow("SPH (Sphere)", text: $leftSphere, field: .leftSphere)
                    fieldRow("CYL (Cylinder)", text: $leftCylinder, field: .leftCylinder)
                    fieldRow("AXIS", text: $leftAxis, field: .leftAxis)
                }

                Section("Right Eye (OD)") {
                    fieldRow("SPH (Sphere)", text: $rightSphere, field: .rightSphere)
                    fieldRow("CYL (Cylinder)", text: $rightCylinder, field: .rightCylinder)
                    fieldRow("AXIS", text: $rightAxis, field: .rightAxis)
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Eye Exam", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .macGroupedFormStyle()
            .navigationTitle(existing == nil ? "Add Eye Exam" : "Edit Eye Exam")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveExam() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if let field = focusedField, field.isSigned {
                        Button("+/−") { toggleSign(for: field) }
                    }
                    Spacer()
                }
            }
            .macSheetFrame(minHeight: 480, idealHeight: 560)
            .alert("Delete Eye Exam", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this eye exam?")
            }
        }
    }

    private func fieldRow(_ label: String, text: Binding<String>, field: EyeField) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.textPrimary)
            Spacer()
            TextField("—", text: text)
                .keyboardType(field.isSigned ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($focusedField, equals: field)
        }
    }

    private func toggleSign(for field: EyeField) {
        let binding: Binding<String>
        switch field {
        case .leftSphere: binding = $leftSphere
        case .leftCylinder: binding = $leftCylinder
        case .rightSphere: binding = $rightSphere
        case .rightCylinder: binding = $rightCylinder
        case .leftAxis, .rightAxis: return
        }
        if binding.wrappedValue.hasPrefix("-") {
            binding.wrappedValue = String(binding.wrappedValue.dropFirst())
        } else if !binding.wrappedValue.isEmpty {
            binding.wrappedValue = "-" + binding.wrappedValue
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
