import SwiftUI

struct OverviewView: View {
    @Binding var selectedTab: Int
    @State private var data: AppData = .empty
    @State private var deathClock: DeathClockEngine.DeathClockResult?
    @State private var lev: DeathClockEngine.LEVResult?
    @State private var countdown: DeathClockEngine.Countdown?
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var isVisible = false
    @State private var todayStr: String = DateFormatting.todayString()
    @State private var weekAgoStr: String = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
    // Pre-sorted arrays to avoid sorting in render path
    @State private var sortedBloodTests: [BloodTest] = []
    @State private var sortedEpigeneticTests: [EpigeneticTest] = []
    @State private var sortedEyeExams: [EyeExam] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                deathClockCard
                if let lev { levCard(lev) }
                vitalStatsRow
                healthGrid
            }
            .padding()
        }
        .background(Color.bg)
        .task { await loadData() }
        .onAppear {
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .onReceive(timer) { _ in guard isVisible else { return }; updateCountdown() }
        .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
            Task { await loadData() }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        let loaded = await DataStore.shared.getData()
        data = loaded
        sortedBloodTests = loaded.bloodTests.sorted(by: { $0.date > $1.date })
        sortedEpigeneticTests = loaded.epigeneticTests.sorted(by: { $0.date > $1.date })
        sortedEyeExams = loaded.eyeExams.sorted(by: { $0.date > $1.date })
        recalculate()
    }

    private func recalculate() {
        todayStr = DateFormatting.todayString()
        weekAgoStr = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())

        guard let birthDate = data.profile.birthDate else {
            deathClock = nil
            lev = nil
            countdown = nil
            return
        }
        deathClock = DeathClockEngine.calculate(
            birthDateStr: birthDate,
            sex: data.profile.biologicalSex,
            lifestyle: data.profile.lifestyle
        )
        if let dc = deathClock {
            lev = DeathClockEngine.calculateLEV(
                birthDateStr: birthDate,
                lifeExpectancy: dc.lifeExpectancy.total
            )
            countdown = DeathClockEngine.countdown(to: dc.deathDate)
        }
    }

    private func updateCountdown() {
        guard let dc = deathClock else { return }
        let newCountdown = DeathClockEngine.countdown(to: dc.deathDate)
        if newCountdown != countdown {
            countdown = newCountdown
        }
    }

    // MARK: - Death Clock Hero Card

    @ViewBuilder
    private var deathClockCard: some View {
        VStack(spacing: 16) {
            if let dc = deathClock, let cd = countdown {
                // Header
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                    Text("Time Remaining")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text(dc.deathDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                // Countdown
                if cd.expired {
                    Text("Time's up.")
                        .font(.title).fontWeight(.bold)
                        .foregroundColor(.danger)
                } else {
                    countdownDisplay(cd)
                }

                Divider().background(Color.cardBorder)

                // Life expectancy breakdown
                VStack(alignment: .leading, spacing: 6) {
                    Text("Life Expectancy Breakdown")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    leBreakdownRow("SSA Baseline", value: dc.lifeExpectancy.baseline, unit: "yr")
                    leBreakdownRow("Genome Adjusted", value: dc.lifeExpectancy.genomeAdjusted, unit: "yr")
                    leBreakdownRow("Lifestyle Adj.", value: dc.lifeExpectancy.lifestyleAdjustment, unit: "yr", signed: true)
                    Divider().background(Color.cardBorder)
                    leBreakdownRow("Total LE", value: dc.lifeExpectancy.total, unit: "yr", bold: true)
                }

                Divider().background(Color.cardBorder)

                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Life Progress")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f%%", dc.percentComplete))
                            .font(.caption).monospacedDigit()
                            .foregroundColor(progressColor(dc.percentComplete))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.bgInput)
                                .frame(height: 10)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor(dc.percentComplete))
                                .frame(width: geo.size.width * min(1, dc.percentComplete / 100), height: 10)
                        }
                    }
                    .frame(height: 10)
                }
            } else {
                // Not configured
                VStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.largeTitle)
                        .foregroundColor(.textMuted)
                    Text("Life Progress")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Configure your birth date and lifestyle in Settings to see your mortality countdown.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    @ViewBuilder
    private func countdownDisplay(_ cd: DeathClockEngine.Countdown) -> some View {
        HStack(spacing: 4) {
            countdownUnit(cd.years, label: "Y", color: .accentColor)
            colonSeparator
            countdownUnit(cd.months, label: "Mo", color: .purple)
            colonSeparator
            countdownUnit(cd.weeks, label: "W", color: .teal)
            colonSeparator
            countdownUnit(cd.days, label: "D", color: .green)
            colonSeparator
            countdownUnit(cd.hours, label: "H", color: .yellow)
            colonSeparator
            countdownUnit(cd.minutes, label: "M", color: .orange)
            colonSeparator
            countdownUnit(cd.seconds, label: "S", color: .red)
        }
    }

    @ViewBuilder
    private func countdownUnit(_ value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2).fontWeight(.bold).monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9)).fontWeight(.medium)
                .foregroundColor(.textMuted)
        }
        .frame(minWidth: 30)
    }

    private var colonSeparator: some View {
        Text(":")
            .font(.title3).fontWeight(.bold)
            .foregroundColor(.textMuted)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private func leBreakdownRow(_ label: String, value: Double, unit: String, signed: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .subheadline.weight(.semibold) : .caption)
                .foregroundColor(bold ? .textPrimary : .textSecondary)
            Spacer()
            Text(signed ? String(format: "%+.1f %@", value, unit) : String(format: "%.1f %@", value, unit))
                .font(bold ? .subheadline.weight(.bold).monospacedDigit() : .caption.monospacedDigit())
                .foregroundColor(bold ? .textPrimary : .textSecondary)
        }
    }

    private func progressColor(_ percent: Double) -> Color {
        if percent >= 80 { return .danger }
        if percent >= 60 { return .warning }
        return .blue
    }

    // MARK: - LEV Card

    @ViewBuilder
    private func levCard(_ lev: DeathClockEngine.LEVResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.shield.fill")
                    .foregroundColor(lev.onTrack ? .success : .warning)
                    .font(.title3)
                Text("Longevity Escape Velocity")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(lev.onTrack ? "On Track" : "At Risk")
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(lev.onTrack ? Color.success.opacity(0.2) : Color.warning.opacity(0.2))
                    .foregroundColor(lev.onTrack ? .success : .warning)
                    .cornerRadius(6)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                levStatItem("Years to LEV", value: "\(lev.yearsToLEV)")
                levStatItem("Age at LEV", value: "\(lev.ageAtLEV)")
                levStatItem("Margin", value: String(format: "%.1f yr", lev.adjustedLifeExpectancy - Double(lev.ageAtLEV)))
                levStatItem("Adjusted LE", value: String(format: "%.1f yr", lev.adjustedLifeExpectancy))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    @ViewBuilder
    private func levStatItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline).monospacedDigit()
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Vital Stats Row

    @ViewBuilder
    private var vitalStatsRow: some View {
        HStack(spacing: 12) {
            vitalStatCard(
                title: "Current Age",
                value: deathClock.map { "\($0.ageYears)" } ?? "--",
                icon: "person.fill",
                color: .blue
            )
            vitalStatCard(
                title: "Years Left",
                value: deathClock.map { String(format: "%.1f", $0.yearsRemaining) } ?? "--",
                icon: "hourglass",
                color: .accentColor
            )
            vitalStatCard(
                title: "Healthy Years",
                value: deathClock.map { String(format: "%.1f", $0.healthyYearsRemaining) } ?? "--",
                icon: "heart.fill",
                color: .success
            )
        }
    }

    @ViewBuilder
    private func vitalStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(value)
                .font(.title2).fontWeight(.bold).monospacedDigit()
                .foregroundColor(.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .cardStyle()
    }

    // MARK: - Health Summary Grid

    @ViewBuilder
    private var healthGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Health Summary")
                .font(.headline)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                alcoholTile
                bodyTile
                bloodTile
                epigeneticTile
                eyesTile
                lifestyleTile
            }
        }
    }

    // MARK: - Alcohol Tile

    @ViewBuilder
    private var alcoholTile: some View {
        let todayDrinks = data.alcoholDrinks.filter { $0.date == todayStr }
        let todayGrams = todayDrinks.reduce(0.0) { $0 + $1.gramsAlcohol }

        let weekDrinks = data.alcoholDrinks.filter { $0.date >= weekAgoStr }
        let weeklyGrams = weekDrinks.reduce(0.0) { $0 + $1.gramsAlcohol }
        let dailyAvg7d = weekDrinks.isEmpty ? 0 : weeklyGrams / 7.0

        let risk = DeathClockEngine.alcoholRisk(drinks: data.alcoholDrinks, sex: data.profile.biologicalSex)

        Button { selectedTab = tabIndex(for: .substances) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "wineglass.fill")
                        .foregroundColor(alcoholRiskColor(risk))
                        .font(.title3)
                    Spacer()
                    Text(risk.rawValue.capitalized)
                        .font(.system(size: 10)).fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(alcoholRiskColor(risk).opacity(0.2))
                        .foregroundColor(alcoholRiskColor(risk))
                        .cornerRadius(4)
                }
                Text(String(format: "%.0fg today", todayGrams))
                    .font(.headline).monospacedDigit()
                    .foregroundColor(.textPrimary)
                Text(String(format: "%.0fg/d avg (7d)", dailyAvg7d))
                    .font(.caption).monospacedDigit()
                    .foregroundColor(.textSecondary)
                Text("Alcohol")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Body Tile

    @ViewBuilder
    private var bodyTile: some View {
        let bmi = data.profile.lifestyle.bmi

        Button { selectedTab = tabIndex(for: .body) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "figure.stand")
                        .foregroundColor(.blue)
                        .font(.title3)
                    Spacer()
                }
                if let bmi {
                    Text(String(format: "BMI %.1f", bmi))
                        .font(.headline).monospacedDigit()
                        .foregroundColor(.textPrimary)
                } else {
                    Text("--")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                }
                Text(data.eyeExams.isEmpty ? "No exams" : "\(data.eyeExams.count) eye exam\(data.eyeExams.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("Body")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Blood Tile

    @ViewBuilder
    private var bloodTile: some View {
        let tests = data.bloodTests
        let latestDate = sortedBloodTests.first?.date

        Button { selectedTab = tabIndex(for: .blood) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                    Spacer()
                }
                Text("\(tests.count) test\(tests.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text(latestDate ?? "No tests")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("Blood")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Epigenetic Tile

    @ViewBuilder
    private var epigeneticTile: some View {
        let latest = sortedEpigeneticTests.first

        Button { selectedTab = tabIndex(for: .body) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "dna")
                        .foregroundColor(.purple)
                        .font(.title3)
                    Spacer()
                }
                if let t = latest {
                    Text(String(format: "Bio %.1f yr", t.biologicalAge))
                        .font(.headline).monospacedDigit()
                        .foregroundColor(.textPrimary)
                    if let pace = t.paceOfAging {
                        Text(String(format: "Pace: %.2f", pace))
                            .font(.caption).monospacedDigit()
                            .foregroundColor(pace < 1 ? .success : .warning)
                    }
                    Text(String(format: "Chrono %.1f yr", t.chronologicalAge))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                } else {
                    Text("--")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("No tests")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                Text("Epigenetic")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Eyes Tile

    @ViewBuilder
    private var eyesTile: some View {
        let exams = data.eyeExams
        let latestDate = sortedEyeExams.first?.date

        Button { selectedTab = tabIndex(for: .body) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.teal)
                        .font(.title3)
                    Spacer()
                }
                Text("\(exams.count) exam\(exams.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text(latestDate ?? "No exams")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("Eyes")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lifestyle Tile

    @ViewBuilder
    private var lifestyleTile: some View {
        let lifestyle = data.profile.lifestyle
        let isConfigured = lifestyle != .default

        Button { selectedTab = tabIndex(for: .lifestyle) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundColor(.green)
                        .font(.title3)
                    Spacer()
                }
                Text(isConfigured ? "Active" : "Not Set")
                    .font(.headline)
                    .foregroundColor(isConfigured ? .success : .textMuted)
                Text(isConfigured ? "Questionnaire complete" : "Tap to configure")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text("Lifestyle")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func alcoholRiskColor(_ risk: DeathClockEngine.AlcoholRisk) -> Color {
        switch risk {
        case .low: return .success
        case .moderate: return .warning
        case .high: return .danger
        }
    }

    private enum TabTarget {
        case body, substances, blood, lifestyle, genome, settings
    }

    private func tabIndex(for target: TabTarget) -> Int {
        // iOS tab order: Overview=0, Body=1, Blood=2, Substances=3, Lifestyle=4, Calendar=5, Genome=6, Settings=7
        switch target {
        case .body: return 1
        case .blood: return 2
        case .substances: return 3
        case .lifestyle: return 4
        case .genome: return 6
        case .settings: return 7
        }
    }
}
