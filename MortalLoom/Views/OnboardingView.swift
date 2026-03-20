import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var biologicalSex: BiologicalSex?
    @State private var smokingStatus: SmokingStatus = .never
    @State private var exerciseMinutes: Double = 150
    @State private var sleepHours: Double = 7.5
    @State private var dietQuality: DietQuality = .good
    @State private var stressLevel: StressLevel = .moderate

    @StateObject private var healthKit = HealthKitService.shared
    @State private var healthKitRequested = false

    private let totalSteps = 9

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                healthKitStep.tag(1)
                birthDateStep.tag(2)
                biologicalSexStep.tag(3)
                smokingStep.tag(4)
                exerciseStep.tag(5)
                sleepStep.tag(6)
                dietStressStep.tag(7)
                resultsStep.tag(8)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            progressDots
                .padding(.bottom, 16)
        }
        .background(Color.bg)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }

    // MARK: - Progress Dots

    @ViewBuilder
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.accentColor : Color.textMuted.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Step 0: Welcome

    @ViewBuilder
    private var welcomeStep: some View {
        stepContainer {
            stepIcon("heart.text.clipboard")
            stepTitle("Welcome to MortalLoom")
            stepDescription("A privacy-first longevity tracker. See how long you might have left \u{2014} and what you can do about it. All data stays on your device.")
            Spacer()
            primaryButton("Get Started") {
                advanceStep()
            }
        }
    }

    // MARK: - Step 1: Apple Health

    @ViewBuilder
    private var healthKitStep: some View {
        stepContainer {
            stepIcon("heart.fill")
            stepTitle("Connect Apple Health")
            stepDescription("MortalLoom can read your health data — steps, heart rate, sleep, weight, and more — to give you a complete picture of your longevity.")

            Spacer()

            if healthKit.isAvailable {
                if healthKitRequested {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("Health access requested")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.text.clipboard")
                            .font(.system(size: 64))
                            .foregroundColor(.pink)

                        Text("Your data never leaves your device.")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.textMuted)
                    Text("Apple Health is not available on this device.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            if healthKit.isAvailable && !healthKitRequested {
                primaryButton("Connect Apple Health") {
                    Task {
                        await healthKit.requestAuthorization()
                        healthKitRequested = true
                        advanceStep()
                    }
                }

                Button {
                    advanceStep()
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            } else {
                primaryButton("Next") {
                    advanceStep()
                }
            }
        }
    }

    // MARK: - Step 2: Birth Date

    @ViewBuilder
    private var birthDateStep: some View {
        stepContainer {
            stepIcon("calendar")
            stepTitle("When were you born?")
            stepDescription("Your birth date is the foundation for all longevity calculations.")

            Spacer()

            #if os(iOS)
            DatePicker("Birth Date", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
            #else
            DatePicker("Birth Date", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: 400)
            #endif

            Spacer()

            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    // MARK: - Step 2: Biological Sex

    @ViewBuilder
    private var biologicalSexStep: some View {
        stepContainer {
            stepIcon("figure.stand")
            stepTitle("Biological Sex")
            stepDescription("Actuarial life expectancy tables differ by biological sex. This helps us calculate your baseline.")

            Spacer()

            HStack(spacing: 16) {
                sexCard("Male", icon: "figure.stand", sex: .male)
                sexCard("Female", icon: "figure.stand.dress", sex: .female)
            }
            .padding(.horizontal)

            Button {
                biologicalSex = nil
                advanceStep()
            } label: {
                Text("Skip / Prefer not to say")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()

            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    @ViewBuilder
    private func sexCard(_ label: String, icon: String, sex: BiologicalSex) -> some View {
        Button {
            biologicalSex = sex
        } label: {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                Text(label)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .foregroundColor(biologicalSex == sex ? .white : .textPrimary)
            .background(biologicalSex == sex ? Color.accentColor : Color.bgCard)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(biologicalSex == sex ? Color.accentColor : Color.cardBorder, lineWidth: biologicalSex == sex ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Smoking

    @ViewBuilder
    private var smokingStep: some View {
        stepContainer {
            stepIcon("smoke")
            stepTitle("Do you smoke?")
            stepDescription("Smoking is the single largest modifiable risk factor for life expectancy.")

            Spacer()

            VStack(spacing: 12) {
                smokingCard("Never", status: .never, impact: "+0y")
                smokingCard("Former", status: .former, impact: "-2y")
                smokingCard("Current", status: .current, impact: "-10y")
            }
            .padding(.horizontal)

            Spacer()

            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    @ViewBuilder
    private func smokingCard(_ label: String, status: SmokingStatus, impact: String) -> some View {
        Button {
            smokingStatus = status
        } label: {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Text(impact)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(impactColor(DeathClockEngine.smokingImpact(status)))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .foregroundColor(smokingStatus == status ? .white : .textPrimary)
            .background(smokingStatus == status ? Color.accentColor : Color.bgCard)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(smokingStatus == status ? Color.accentColor : Color.cardBorder, lineWidth: smokingStatus == status ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: Exercise

    @ViewBuilder
    private var exerciseStep: some View {
        stepContainer {
            stepIcon("figure.run")
            stepTitle("How much do you exercise?")
            stepDescription("WHO recommends at least 150 minutes of moderate activity per week.")

            Spacer()

            VStack(spacing: 8) {
                Text("\(Int(exerciseMinutes))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("minutes per week")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)

                impactBadge(DeathClockEngine.exerciseImpact(Int(exerciseMinutes)))
                    .padding(.top, 4)
            }

            Slider(value: $exerciseMinutes, in: 0...600, step: 15)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .tint(.accentColor)

            HStack {
                Text("0 min")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                Spacer()
                Text("600 min")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding(.horizontal, 32)

            Spacer()

            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    // MARK: - Step 5: Sleep

    @ViewBuilder
    private var sleepStep: some View {
        stepContainer {
            stepIcon("bed.double")
            stepTitle("How much sleep do you get?")
            stepDescription("Optimal sleep for longevity is 7-9 hours per night.")

            Spacer()

            VStack(spacing: 8) {
                Text(String(format: "%.1f", sleepHours))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("hours per night")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)

                impactBadge(DeathClockEngine.sleepImpact(sleepHours))
                    .padding(.top, 4)
            }

            Slider(value: $sleepHours, in: 3...12, step: 0.5)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .tint(.accentColor)

            HStack {
                Text("3 hrs")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                Spacer()
                Text("12 hrs")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding(.horizontal, 32)

            Spacer()

            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    // MARK: - Step 6: Diet & Stress

    @ViewBuilder
    private var dietStressStep: some View {
        stepContainer {
            stepIcon("leaf")
            stepTitle("Diet & Stress")
            stepDescription("Rate your overall diet quality and stress level.")

            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Diet Quality")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(DietQuality.allCases, id: \.self) { quality in
                            choiceButton(quality.rawValue.capitalized, isSelected: dietQuality == quality) {
                                dietQuality = quality
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Stress Level")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(StressLevel.allCases, id: \.self) { level in
                            choiceButton(level.rawValue.capitalized, isSelected: stressLevel == level) {
                                stressLevel = level
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    impactBadge(DeathClockEngine.dietImpact(dietQuality) + DeathClockEngine.stressImpact(stressLevel))
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)

            Spacer()

            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    @ViewBuilder
    private func choiceButton(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline).fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .foregroundColor(isSelected ? .white : .textPrimary)
                .background(isSelected ? Color.accentColor : Color.bgCard)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : Color.cardBorder, lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 7: Results

    @ViewBuilder
    private var resultsStep: some View {
        let birthDateStr = DateFormatting.dateString(birthDate)
        let lifestyle = LifestyleData(
            smokingStatus: smokingStatus,
            exerciseMinutesPerWeek: Int(exerciseMinutes),
            sleepHoursPerNight: sleepHours,
            dietQuality: dietQuality,
            stressLevel: stressLevel,
            bmi: nil
        )
        let result = DeathClockEngine.calculate(birthDateStr: birthDateStr, sex: biologicalSex, lifestyle: lifestyle)

        stepContainer {
            stepIcon("clock")
            stepTitle("Your Life Expectancy")

            if let result {
                let baseline = result.lifeExpectancy.baseline
                let adjustment = result.lifeExpectancy.lifestyleAdjustment
                let total = result.lifeExpectancy.total

                VStack(spacing: 16) {
                    // Baseline
                    HStack {
                        Text("SSA Baseline")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f years", baseline))
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                    }

                    // Adjustment
                    HStack {
                        Text("Lifestyle Adjustment")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(String(format: "%+.1f years", adjustment))
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(impactColor(adjustment))
                    }

                    Divider().background(Color.cardBorder)

                    // Final LE
                    HStack {
                        Text("Life Expectancy")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f years", total))
                            .font(.headline).fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }

                    // Projected death date
                    HStack {
                        Text("Projected Date")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(DateFormatting.displayDate(DateFormatting.dateString(result.deathDate)))
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                    }
                }
                .padding()
                .cardStyle()
                .padding(.horizontal)

                Spacer()

                // Death clock countdown preview
                let countdown = DeathClockEngine.countdown(to: result.deathDate)
                VStack(spacing: 8) {
                    Text("Time Remaining")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textMuted)
                        .tracking(1)

                    HStack(spacing: 12) {
                        countdownUnit("\(countdown.years)", label: "YRS")
                        countdownUnit("\(countdown.months)", label: "MO")
                        countdownUnit("\(countdown.weeks)", label: "WK")
                        countdownUnit("\(countdown.days)", label: "DAYS")
                    }
                }
                .padding()
                .cardStyle()
                .padding(.horizontal)
            } else {
                Spacer()
                Text("Unable to calculate. Please go back and check your inputs.")
                    .font(.subheadline)
                    .foregroundColor(.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            primaryButton("Start Your Journey") {
                saveAndDismiss()
            }
        }
    }

    @ViewBuilder
    private func countdownUnit(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.textMuted)
                .tracking(0.5)
        }
        .frame(minWidth: 50)
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func stepContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16) {
            content()
        }
        .padding(.horizontal, 24)
        .padding(.top, 48)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 48))
            .foregroundColor(.accentColor)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func stepTitle(_ text: String) -> some View {
        Text(text)
            .font(.title).fontWeight(.bold)
            .foregroundColor(.textPrimary)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func stepDescription(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func impactBadge(_ years: Double) -> some View {
        let text = years >= 0 ? String(format: "+%.1f years", years) : String(format: "%.1f years", years)
        Text(text)
            .font(.subheadline).fontWeight(.semibold)
            .foregroundColor(impactColor(years))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(impactColor(years).opacity(0.12))
            .cornerRadius(8)
    }

    // MARK: - Helpers

    private func impactColor(_ value: Double) -> Color {
        if value > 0 { return .success }
        if value < 0 { return .danger }
        return .textSecondary
    }

    private func advanceStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }

    private func saveAndDismiss() {
        let birthDateStr = DateFormatting.dateString(birthDate)
        let lifestyle = LifestyleData(
            smokingStatus: smokingStatus,
            exerciseMinutesPerWeek: Int(exerciseMinutes),
            sleepHoursPerNight: sleepHours,
            dietQuality: dietQuality,
            stressLevel: stressLevel,
            bmi: nil
        )
        let profile = HealthProfile(
            birthDate: birthDateStr,
            biologicalSex: biologicalSex,
            lifestyle: lifestyle
        )
        Task {
            await DataStore.shared.updateProfile(profile)
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
            isPresented = false
        }
    }
}
