import SwiftUI

struct LifestyleView: View {
    @State private var biologicalSex: BiologicalSex? = nil
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var hasBirthDate = false

    @State private var smokingStatus: SmokingStatus = .never
    @State private var exerciseMinutes: Double = 150
    @State private var sleepHours: Double = 7.5
    @State private var dietQuality: DietQuality = .good
    @State private var stressLevel: StressLevel = .moderate
    @State private var bmiText: String = ""

    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileSection
                questionnaireSection
                saveSection
                impactPreviewSection
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle("Lifestyle")
        .task { await loadData() }
    }

    // MARK: - Profile Section

    @ViewBuilder
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "PROFILE")

            VStack(alignment: .leading, spacing: 8) {
                Text("Biological Sex")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textSecondary)

                Picker("Biological Sex", selection: $biologicalSex) {
                    Text("Not Set").tag(BiologicalSex?.none)
                    Text("Male").tag(BiologicalSex?.some(.male))
                    Text("Female").tag(BiologicalSex?.some(.female))
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Birth Date")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textSecondary)

                DatePicker(
                    "Birth Date",
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .onChange(of: birthDate) { _, _ in hasBirthDate = true }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Questionnaire Section

    @ViewBuilder
    private var questionnaireSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "LIFESTYLE QUESTIONNAIRE")

            // Smoking
            VStack(alignment: .leading, spacing: 8) {
                Text("Smoking Status")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textSecondary)

                Picker("Smoking Status", selection: $smokingStatus) {
                    ForEach(SmokingStatus.allCases, id: \.self) { status in
                        Text(status.rawValue.capitalized).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Exercise
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Exercise")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(Int(exerciseMinutes)) min/week")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(exerciseColor)
                }

                Slider(value: $exerciseMinutes, in: 0...600, step: 15)
                    .tint(.accentColor)

                Text("WHO recommends 150+ min/week")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }

            // Sleep
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sleep")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f hrs/night", sleepHours))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(sleepColor)
                }

                Slider(value: $sleepHours, in: 3...12, step: 0.5)
                    .tint(.accentColor)

                Text("Optimal: 7-9 hours")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }

            // Diet Quality
            VStack(alignment: .leading, spacing: 8) {
                Text("Diet Quality")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textSecondary)

                Picker("Diet Quality", selection: $dietQuality) {
                    ForEach(DietQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue.capitalized).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Stress Level
            VStack(alignment: .leading, spacing: 8) {
                Text("Stress Level")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textSecondary)

                Picker("Stress Level", selection: $stressLevel) {
                    ForEach(StressLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            // BMI
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("BMI")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    if let bmi = parsedBMI {
                        Text(bmiLabel(bmi))
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(bmiColor(bmi))
                    }
                }

                TextField("Enter BMI (e.g. 22.5)", text: $bmiText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.bgInput)
                    .cornerRadius(8)
                    .foregroundColor(.textPrimary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Save Section

    @ViewBuilder
    private var saveSection: some View {
        Button {
            Task { await saveData() }
        } label: {
            HStack {
                Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                Text(saved ? "Saved" : "Save Lifestyle Profile")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(saved ? .success : .accentColor)
        .disabled(saved)
        .onChange(of: smokingStatus) { _, _ in saved = false }
        .onChange(of: exerciseMinutes) { _, _ in saved = false }
        .onChange(of: sleepHours) { _, _ in saved = false }
        .onChange(of: dietQuality) { _, _ in saved = false }
        .onChange(of: stressLevel) { _, _ in saved = false }
        .onChange(of: bmiText) { _, _ in saved = false }
        .onChange(of: biologicalSex) { _, _ in saved = false }
        .onChange(of: birthDate) { _, _ in saved = false }
    }

    // MARK: - Impact Preview

    @ViewBuilder
    private var impactPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "IMPACT PREVIEW")

            Text("How your lifestyle factors affect life expectancy")
                .font(.caption)
                .foregroundColor(.textMuted)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                impactCard(
                    icon: "nosign",
                    title: "Smoking",
                    value: smokingImpact,
                    detail: smokingStatus.rawValue.capitalized
                )
                impactCard(
                    icon: "figure.run",
                    title: "Exercise",
                    value: exerciseImpact,
                    detail: "\(Int(exerciseMinutes)) min/wk"
                )
                impactCard(
                    icon: "bed.double.fill",
                    title: "Sleep",
                    value: sleepImpact,
                    detail: String(format: "%.1fh", sleepHours)
                )
                impactCard(
                    icon: "fork.knife",
                    title: "Diet",
                    value: dietImpact,
                    detail: dietQuality.rawValue.capitalized
                )
                impactCard(
                    icon: "brain.head.profile",
                    title: "Stress",
                    value: stressImpact,
                    detail: stressLevel.rawValue.capitalized
                )
                impactCard(
                    icon: "scalemass.fill",
                    title: "BMI",
                    value: bmiImpact,
                    detail: parsedBMI.map { String(format: "%.1f", $0) } ?? "Not set"
                )
            }

            // Total
            HStack {
                Text("Total Adjustment")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(formatYears(totalImpact))
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(impactColor(totalImpact))
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private func impactCard(icon: String, title: String, value: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.textSecondary)
                    .font(.caption)
                Spacer()
                Text(formatYears(value))
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(impactColor(value))
            }
            Text(title)
                .font(.caption).fontWeight(.medium)
                .foregroundColor(.textPrimary)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
        .padding(10)
        .background(Color.bgInput)
        .cornerRadius(8)
    }

    // MARK: - Impact Calculations

    private var smokingImpact: Double {
        DeathClockEngine.smokingImpact(smokingStatus)
    }

    private var exerciseImpact: Double {
        DeathClockEngine.exerciseImpact(Int(exerciseMinutes))
    }

    private var sleepImpact: Double {
        DeathClockEngine.sleepImpact(sleepHours)
    }

    private var dietImpact: Double {
        DeathClockEngine.dietImpact(dietQuality)
    }

    private var stressImpact: Double {
        DeathClockEngine.stressImpact(stressLevel)
    }

    private var bmiImpact: Double {
        DeathClockEngine.bmiImpact(parsedBMI)
    }

    private var totalImpact: Double {
        smokingImpact + exerciseImpact + sleepImpact + dietImpact + stressImpact + bmiImpact
    }

    // MARK: - Helpers

    private var parsedBMI: Double? {
        let trimmed = bmiText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var exerciseColor: Color {
        if exerciseMinutes > 150 { return .success }
        if exerciseMinutes >= 75 { return .warning }
        return .danger
    }

    private var sleepColor: Color {
        if sleepHours >= 7 && sleepHours <= 9 { return .success }
        if sleepHours >= 6 { return .warning }
        return .danger
    }

    private func bmiLabel(_ bmi: Double) -> String {
        if bmi < 18.5 { return "Underweight" }
        if bmi < 25 { return "Normal" }
        if bmi < 30 { return "Overweight" }
        return "Obese"
    }

    private func bmiColor(_ bmi: Double) -> Color {
        if bmi < 18.5 { return .warning }
        if bmi < 25 { return .success }
        if bmi < 30 { return .warning }
        return .danger
    }

    private func impactColor(_ value: Double) -> Color {
        if value > 0 { return .success }
        if value < 0 { return .danger }
        return .textSecondary
    }

    private func formatYears(_ value: Double) -> String {
        if value > 0 { return "+\(formatNumber(value)) yrs" }
        if value < 0 { return "\(formatNumber(value)) yrs" }
        return "0 yrs"
    }

    private func formatNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    // MARK: - Data Persistence

    private func loadData() async {
        let data = await DataStore.shared.getData()
        let profile = data.profile
        let lifestyle = profile.lifestyle

        if let sex = profile.biologicalSex {
            biologicalSex = sex
        }
        if let dateStr = profile.birthDate,
           let date = DeathClockEngine.dateFromString(dateStr) {
            birthDate = date
            hasBirthDate = true
        }

        smokingStatus = lifestyle.smokingStatus
        exerciseMinutes = Double(lifestyle.exerciseMinutesPerWeek)
        sleepHours = lifestyle.sleepHoursPerNight
        dietQuality = lifestyle.dietQuality
        stressLevel = lifestyle.stressLevel
        if let bmi = lifestyle.bmi {
            bmiText = String(format: "%.1f", bmi)
        }
    }

    private func saveData() async {
        let lifestyle = LifestyleData(
            smokingStatus: smokingStatus,
            exerciseMinutesPerWeek: Int(exerciseMinutes),
            sleepHoursPerNight: sleepHours,
            dietQuality: dietQuality,
            stressLevel: stressLevel,
            bmi: parsedBMI
        )

        let birthDateStr: String? = hasBirthDate
            ? DeathClockEngine.dateString(birthDate)
            : nil

        let profile = HealthProfile(
            birthDate: birthDateStr,
            biologicalSex: biologicalSex,
            lifestyle: lifestyle
        )

        await DataStore.shared.updateProfile(profile)
        saved = true
        NotificationCenter.default.post(name: .profileDidChange, object: nil)
    }
}
