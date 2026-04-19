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

    // Location / environment
    @State private var countryCode: String? = nil
    @State private var regionCode: String? = nil
    @State private var regionOptions: [(name: String, code: String)] = []
    @State private var airQuality: AirQualityLevel? = nil
    @State private var useAutoDetect: Bool = false
    @State private var locationService = LocationService.shared

    // Socioeconomic (optional, all "prefer not to say" by default)
    @State private var education: EducationLevel? = nil
    @State private var incomeBracket: IncomeBracket? = nil

    @State private var saved = false
    @State private var hasHealthKitSleep = false
    @State private var hasHealthKitExercise = false
    @State private var sleepStageBreakdown: SleepEngine.SleepStageBreakdown? = nil
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            Group {
                if isWide { wideLayout } else { narrowLayout }
            }
            .padding()
            .readContainerWidth { containerWidth = $0 }
        }
        .background(Color.bg)
        .toast($toastMessage)
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
    }

    @ViewBuilder
    private var narrowLayout: some View {
        VStack(spacing: 16) {
            profileSection
            questionnaireSection
            environmentSection
            socioeconomicSection
            saveSection
            impactPreviewSection
        }
    }

    @ViewBuilder
    private var wideLayout: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    profileSection
                    environmentSection
                    socioeconomicSection
                    saveSection
                }
                .frame(maxWidth: .infinity)
                questionnaireSection
                    .frame(maxWidth: .infinity)
            }
            impactPreviewSection
        }
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

    // MARK: - Environment Section

    @ViewBuilder
    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "ENVIRONMENT")

            // Country
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Country")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    if useAutoDetect {
                        autoDetectButton
                    }
                }

                if useAutoDetect && locationService.status == .denied {
                    Text("Location access denied. Enable in Settings or select your country manually.")
                        .font(.caption)
                        .foregroundColor(.warning)
                }

                Picker("Country", selection: $countryCode) {
                    Text("Not set").tag(String?.none)
                    ForEach(LocationEngine.countriesForPicker, id: \.code) { entry in
                        Text(entry.name).tag(String?.some(entry.code))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: countryCode) { _, new in
                    saved = false
                    let prefix = (new ?? "").uppercased() + "-"
                    if regionCode?.hasPrefix(prefix) != true { regionCode = nil }
                    regionOptions = new.map { LocationEngine.regionsForPicker(countryCode: $0) } ?? []
                }

                if !regionOptions.isEmpty {
                    Picker("State / Region", selection: $regionCode) {
                        Text("Not set").tag(String?.none)
                        ForEach(regionOptions, id: \.code) { entry in
                            Text(entry.name).tag(String?.some(entry.code))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: regionCode) { _, _ in saved = false }
                }

                Toggle("Auto-detect from location", isOn: $useAutoDetect)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .toggleStyle(.switch)
                    .onChange(of: useAutoDetect) { _, on in
                        saved = false
                        if on { Task { await triggerAutoDetect() } }
                    }
            }

            // Air quality
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Air Quality")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    if let aq = airQuality {
                        Text(aq.rawValue)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(airQualityColor(aq))
                    } else {
                        Text("Not set")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                }

                Picker("Air Quality", selection: $airQuality) {
                    Text("Not set").tag(AirQualityLevel?.none)
                    ForEach(AirQualityLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(AirQualityLevel?.some(level))
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: airQuality) { _, _ in saved = false }

                if let aq = airQuality {
                    Text(aq.description)
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                Text("Country LE is based on WHO 2022 data relative to the US SSA baseline. Air quality reflects long-term PM2.5 exposure impact.")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                CitationBadge(
                    ids: [
                        CitationLibrary.whoLifeExpectancy.id,
                        CitationLibrary.lancetPollution2018.id,
                        CitationLibrary.ssaLifeTable.id,
                    ],
                    claim: "Country and air-quality life-expectancy adjustments"
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private var autoDetectButton: some View {
        Button {
            Task { await triggerAutoDetect() }
        } label: {
            switch locationService.status {
            case .requesting, .detecting:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Detecting…").font(.caption)
                }
            case .done:
                Label("Detected", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundColor(.success)
            case .denied:
                Label("Denied", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundColor(.danger)
            default:
                Label("Detect", systemImage: "location")
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(locationService.status == .requesting || locationService.status == .detecting)
    }

    private func triggerAutoDetect() async {
        await locationService.detect()
        if let code = locationService.detectedCountryCode {
            countryCode = code
            saved = false
        }
        if let region = locationService.detectedRegionCode {
            regionCode = region
        }
        // Fetch air quality from the transient coordinate, then clear it so the
        // coordinate never lingers in memory or gets persisted.
        if let coord = locationService.lastCoordinate {
            let reading = await AirQualityService.fetch(coordinate: coord)
            locationService.clearCoordinate()
            if let reading {
                airQuality = reading.level
                saved = false
                showToast($toastMessage, message: "Air quality: \(reading.level.rawValue) (AQI \(reading.usAQI))")
            }
        }
    }

    private func airQualityColor(_ level: AirQualityLevel) -> Color {
        switch level {
        case .good:      return .success
        case .moderate:  return .textSecondary
        case .unhealthy: return .warning
        case .hazardous: return .danger
        }
    }

    // MARK: - Socioeconomic Section

    @ViewBuilder
    private var socioeconomicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                SectionLabel(text: "SOCIOECONOMIC")
                Spacer()
                CitationBadge(
                    ids: [
                        CitationLibrary.chettyIncomeLE2016.id,
                        CitationLibrary.nchsEducationLE2012.id,
                    ],
                    claim: "Income and education effects on life expectancy"
                )
            }

            Text("Optional. Income and education are among the strongest non-biological predictors of longevity. Stored only on your device.")
                .font(.caption)
                .foregroundColor(.textMuted)

            VStack(alignment: .leading, spacing: 8) {
                Text("Highest Education")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textSecondary)

                Picker("Education", selection: $education) {
                    Text("Prefer not to say").tag(EducationLevel?.none)
                    ForEach(EducationLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(EducationLevel?.some(level))
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Household Income Bracket")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textSecondary)

                Picker("Income", selection: $incomeBracket) {
                    Text("Prefer not to say").tag(IncomeBracket?.none)
                    ForEach(IncomeBracket.allCases, id: \.self) { bracket in
                        Text(bracket.displayName).tag(IncomeBracket?.some(bracket))
                    }
                }
                .pickerStyle(.menu)
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

                if hasHealthKitExercise {
                    HStack(spacing: 4) {
                        Image(systemName: "applelogo")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text("Synced from Apple Health (7-day total)")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                } else {
                    Slider(value: $exerciseMinutes, in: 0...600, step: 15)
                        .tint(.accentColor)
                        .accessibilityLabel("Exercise minutes per week")
                        .accessibilityValue("\(Int(exerciseMinutes)) minutes")
                }

                HStack(spacing: 4) {
                    Text("WHO recommends 150+ min/week")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                    CitationBadge(
                        ids: [
                            CitationLibrary.whoPhysicalActivity.id,
                            CitationLibrary.arem2015Exercise.id,
                        ],
                        claim: "WHO 150 min/week recommendation"
                    )
                }
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

                if hasHealthKitSleep {
                    HStack(spacing: 4) {
                        Image(systemName: "applelogo")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text("Synced from Apple Health")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                    if let stages = sleepStageBreakdown {
                        Text("Deep: \(stages.deepQuality.rawValue) · REM: \(stages.remQuality.rawValue)")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                } else {
                    Slider(value: $sleepHours, in: 3...12, step: 0.5)
                        .tint(.accentColor)
                        .accessibilityLabel("Sleep hours per night")
                        .accessibilityValue(String(format: "%.1f hours", sleepHours))
                    HStack(spacing: 4) {
                        Text("Optimal: 7-9 hours")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                        CitationBadge(
                            ids: [
                                CitationLibrary.cappuccioSleep2010.id,
                                CitationLibrary.nsfSleepDuration.id,
                            ],
                            claim: "7-9h optimal sleep duration"
                        )
                    }
                }
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
                    .accessibilityLabel("Body mass index")
                    .accessibilityHint("Enter your BMI as a decimal number")
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
        .onChange(of: regionCode) { _, _ in saved = false }
        .onChange(of: airQuality) { _, _ in saved = false }
        .onChange(of: education) { _, _ in saved = false }
        .onChange(of: incomeBracket) { _, _ in saved = false }
    }

    // MARK: - Impact Preview

    @ViewBuilder
    private var impactPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "IMPACT PREVIEW")

            Text("How your lifestyle factors affect life expectancy")
                .font(.caption)
                .foregroundColor(.textMuted)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: isWide ? 3 : 2), spacing: 10) {
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
                impactCard(
                    icon: "globe",
                    title: "Country",
                    value: countryImpact,
                    detail: countryCode.map { LocationEngine.countryDisplayName($0) } ?? "Not set"
                )
                if let rc = regionCode {
                    impactCard(
                        icon: "map",
                        title: "Region",
                        value: regionImpact,
                        detail: LocationEngine.regionDisplayName(rc)
                    )
                }
                impactCard(
                    icon: "aqi.medium",
                    title: "Air Quality",
                    value: airQualityImpact,
                    detail: airQuality?.rawValue ?? "Not set"
                )
                if education != nil || incomeBracket != nil {
                    impactCard(
                        icon: "building.columns",
                        title: "Socioeconomic",
                        value: socioeconomicImpact,
                        detail: socioeconomicDetail
                    )
                }
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total lifestyle adjustment: \(String(format: "%+.1f", totalImpact)) years on life expectancy")

            CitationSourceRow(
                label: "Sources: SSA · WHO · peer-reviewed research",
                ids: [
                    CitationLibrary.ssaLifeTable.id,
                    CitationLibrary.whoPhysicalActivity.id,
                    CitationLibrary.arem2015Exercise.id,
                    CitationLibrary.cappuccioSleep2010.id,
                    CitationLibrary.nsfSleepDuration.id,
                    CitationLibrary.whoBmi.id,
                    CitationLibrary.bmiMortality2016.id,
                    CitationLibrary.dollSmoking2004.id,
                    CitationLibrary.predimedMedDiet.id,
                    CitationLibrary.epelTelomere2004.id,
                ],
                claim: "Every factor shown above maps to one or more of these sources."
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private func impactCard(icon: String, title: String, value: Double, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.textSecondary)
                .font(.caption)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            Spacer(minLength: 4)
            Text(formatYears(value))
                .font(.subheadline).fontWeight(.bold)
                .foregroundColor(impactColor(value))
        }
        .padding(10)
        .background(Color.bgInput)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail), \(String(format: "%+.1f", value)) years impact")
    }

    // MARK: - Impact Calculations

    private var smokingImpact: Double {
        DeathClockEngine.smokingImpact(smokingStatus)
    }

    private var exerciseImpact: Double {
        DeathClockEngine.exerciseImpact(Int(exerciseMinutes))
    }

    private var sleepImpact: Double {
        SleepEngine.enhancedLongevityImpact(averageHours: sleepHours, stageBreakdown: sleepStageBreakdown)
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

    private var countryImpact: Double {
        LocationEngine.countryLifeExpectancyDelta(countryCode ?? "")
    }

    private var regionImpact: Double {
        LocationEngine.regionLifeExpectancyDelta(regionCode ?? "")
    }

    private var airQualityImpact: Double {
        LocationEngine.airQualityAdjustment(airQuality)
    }

    private var socioeconomicImpact: Double {
        DeathClockEngine.socioeconomicImpact(
            SocioeconomicProfile(education: education, incomeBracket: incomeBracket)
        )
    }

    private var socioeconomicDetail: String {
        switch (education, incomeBracket) {
        case let (.some(e), .some(i)): return "\(e.rawValue) · \(i.rawValue)"
        case let (.some(e), .none):    return e.displayName
        case let (.none, .some(i)):    return i.displayName
        case (.none, .none):           return "Not set"
        }
    }

    private var totalImpact: Double {
        smokingImpact + exerciseImpact + sleepImpact + dietImpact + stressImpact + bmiImpact
        + countryImpact + regionImpact + airQualityImpact + socioeconomicImpact
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
        // Use the shared DateFormatting helper instead of duplicating the
        // truncatingRemainder formatter inline. The two are character-identical.
        if value > 0 { return "+\(DateFormatting.formatMarkerValue(value)) yrs" }
        if value < 0 { return "\(DateFormatting.formatMarkerValue(value)) yrs" }
        return "0 yrs"
    }

    // MARK: - Data Persistence

    private func loadData() async {
        let data = await DataStore.shared.getData()
        let profile = data.profile
        let lifestyle = profile.lifestyle

        let sleepVals = data.healthMetrics.compactMap(\.sleepHours)
        hasHealthKitSleep = sleepVals.count >= 3
        sleepStageBreakdown = hasHealthKitSleep ? SleepEngine.stageBreakdown(metrics: data.healthMetrics) : nil

        // Exercise is daily minutes of appleExerciseTime. Require 3+ days of data
        // in the last 7 to consider HealthKit the source of truth.
        let last7 = Set((0..<7).map { DateFormatting.dateString(daysAgo: $0) })
        let exerciseDays = data.healthMetrics.filter { last7.contains($0.date) }.compactMap(\.exerciseMinutes)
        hasHealthKitExercise = exerciseDays.count >= 3

        if let sex = profile.biologicalSex {
            biologicalSex = sex
        }
        if let dateStr = profile.birthDate,
           let date = DeathClockEngine.dateFromString(dateStr) {
            birthDate = date
            hasBirthDate = true
        }

        smokingStatus = lifestyle.smokingStatus
        if hasHealthKitExercise {
            exerciseMinutes = Double(Int(exerciseDays.reduce(0, +).rounded()))
        } else {
            exerciseMinutes = Double(lifestyle.exerciseMinutesPerWeek)
        }
        if hasHealthKitSleep {
            sleepHours = (sleepVals.reduce(0, +) / Double(sleepVals.count) * 10).rounded() / 10
        } else {
            sleepHours = lifestyle.sleepHoursPerNight
        }
        dietQuality = lifestyle.dietQuality
        stressLevel = lifestyle.stressLevel
        if let bmi = lifestyle.bmi {
            bmiText = String(format: "%.1f", bmi)
        }

        if let loc = profile.locationProfile {
            countryCode = loc.countryCode
            regionCode = loc.regionCode
            airQuality = loc.airQuality
            useAutoDetect = loc.useAutoDetect
            regionOptions = loc.countryCode.map { LocationEngine.regionsForPicker(countryCode: $0) } ?? []
        }

        if let ses = profile.socioeconomic {
            education = ses.education
            incomeBracket = ses.incomeBracket
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

        let locationProfile = LocationProfile(
            countryCode: countryCode,
            regionCode: regionCode,
            airQuality: airQuality,
            useAutoDetect: useAutoDetect
        )

        let socioeconomic: SocioeconomicProfile? = (education != nil || incomeBracket != nil)
            ? SocioeconomicProfile(education: education, incomeBracket: incomeBracket)
            : nil

        // Load existing to preserve countdownMode, levTargetAge, and any future fields
        var existingData = await DataStore.shared.getData()
        existingData.profile.birthDate = birthDateStr
        existingData.profile.biologicalSex = biologicalSex
        existingData.profile.lifestyle = lifestyle
        existingData.profile.locationProfile = locationProfile
        existingData.profile.socioeconomic = socioeconomic
        await DataStore.shared.updateProfile(existingData.profile)
        saved = true
        NotificationCenter.default.post(name: .profileDidChange, object: nil)
        showToast($toastMessage, message: "Lifestyle profile saved")
    }
}
