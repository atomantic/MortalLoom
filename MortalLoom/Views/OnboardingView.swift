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

    @State private var healthKit = HealthKitService.shared
    @State private var healthKitRequested = false
    @State private var healthKitRequestFailed = false
    @State private var lifeExpectancyResult: DeathClockEngine.DeathClockResult?

    @State private var apexGoalTitle: String = ""
    @State private var apexGoalNotes: String = ""
    @State private var apexGoalCategory: GoalCategory? = nil

    // First reflection seed — answered after the user names their North Star.
    // Stored as an initial reflection-shaped GoalCheckIn on the new apex so
    // the Reflections journal has content from day one.
    @State private var firstReflectionAnswer: String = ""
    // Default 5 ("Mixed") rather than 7 ("Mostly aligned") so we don't tell
    // the user how they feel before they've engaged.
    @State private var firstReflectionRating: Double = 5

    private let totalSteps = 13

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $currentStep) {
                // Order reflects the app's framing: start with what matters
                // to the user (North Star → first reflection), then introduce
                // longevity as the way to extend the runway for those goals.
                welcomeStep.tag(0)
                planYourLifeStep.tag(1)
                apexGoalStep.tag(2)
                firstReflectionStep.tag(3)
                escapeVelocityStep.tag(4)
                healthKitStep.tag(5)
                birthDateStep.tag(6)
                biologicalSexStep.tag(7)
                smokingStep.tag(8)
                exerciseStep.tag(9)
                sleepStep.tag(10)
                dietStressStep.tag(11)
                resultsStep.tag(12)
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

    // MARK: - Top Bar (back button)

    @ViewBuilder
    private var topBar: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(height: 44)
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = max(currentStep - 1, 0)
        }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
    }

    // MARK: - Step 0: Welcome (tag 0)

    private var companionPlatformName: String {
        #if os(macOS)
        return "iPhone & iPad"
        #else
        return "Mac"
        #endif
    }

    @ViewBuilder
    private var welcomeStep: some View {
        stepContainer {
            stepIcon("heart.text.clipboard")
            stepTitle("Welcome to MortalLoom")
            stepDescription("Plan your life around what matters. Track your health, set goals with real deadlines, and make every year count.")

            VStack(alignment: .leading, spacing: 14) {
                privacyBullet(
                    icon: "target",
                    title: "Goals with real deadlines",
                    detail: "Set life goals tied to your health trajectory. MortalLoom helps you plan with the time you actually have."
                )
                privacyBullet(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Track what moves the needle",
                    detail: "Sleep, exercise, blood markers, genome \u{2014} see exactly how your habits affect your longevity estimate."
                )
                privacyBullet(
                    icon: "lock.shield.fill",
                    title: "Private by design",
                    detail: "No accounts, no servers, no telemetry. Your data syncs via your iCloud and never leaves your devices."
                )
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Spacer()
            primaryButton("Get Started") {
                advanceStep()
            }
        }
    }

    @ViewBuilder
    private func privacyBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Step 1: Plan Your Life (tag 1)

    @ViewBuilder
    private var planYourLifeStep: some View {
        stepContainer {
            stepIcon("calendar.badge.clock")
            stepTitle("Plan Your Life")
            stepDescription("Your time is finite. MortalLoom helps you use it intentionally.")

            VStack(alignment: .leading, spacing: 14) {
                privacyBullet(
                    icon: "book.fill",
                    title: "Want to write a book?",
                    detail: "That takes planning and time. Set it as a goal, give it a deadline, and MortalLoom shows you where it fits in your life."
                )
                privacyBullet(
                    icon: "exclamationmark.triangle.fill",
                    title: "Falling behind on goals?",
                    detail: "Maybe it\u{2019}s time to reprioritize \u{2014} or examine the habits that are eating into your available years."
                )
                privacyBullet(
                    icon: "arrow.trianglehead.counterclockwise.rotate.90",
                    title: "Your habits shape your timeline",
                    detail: "Every lifestyle choice shifts your projected lifespan. Improving your health doesn\u{2019}t just add years \u{2014} it adds years to accomplish what matters to you."
                )
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Spacer()
            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    // MARK: - Step 4: Longevity Escape Velocity (tag 4)

    @ViewBuilder
    private var escapeVelocityStep: some View {
        stepContainer {
            Image("EscapeVelocity")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .padding(.horizontal, -24)
                .padding(.bottom, 4)
                .accessibilityLabel("A glowing DNA helix curving upward into an arrow, symbolizing accelerating longevity")
            stepTitle("Longevity Escape Velocity")
            stepDescription("The reason every healthy year right now matters more than the last.")

            VStack(alignment: .leading, spacing: 14) {
                privacyBullet(
                    icon: "hourglass",
                    title: "You age 1 year per year",
                    detail: "That has always been the deal \u{2014} until recently."
                )
                privacyBullet(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Medicine is catching up",
                    detail: "Each year, breakthroughs in geroscience, gene therapy, and AI-driven diagnostics add measurable months to expected lifespan."
                )
                privacyBullet(
                    icon: "infinity",
                    title: "Escape velocity",
                    detail: "When research adds more than a year of life expectancy per calendar year, the finish line stops moving toward you. Reach it in good health and the math tilts in your favor."
                )
                privacyBullet(
                    icon: "figure.run.circle.fill",
                    title: "Your job: stay in the game",
                    detail: "MortalLoom tracks the levers you control \u{2014} sleep, movement, substances, blood markers, genome \u{2014} so you can buy yourself time until the curve crosses."
                )
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Spacer()
            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    // MARK: - Step 5: Apple Health (tag 5)

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
                        if healthKitRequestFailed {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.warning)
                            Text("Health permission request failed. You can try again via Settings > Privacy > Health.")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("Health access granted")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                        }
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
                primaryButton("Continue") {
                    Task {
                        await healthKit.requestAuthorization()
                        healthKitRequestFailed = !healthKit.authorizationRequestCompleted
                        healthKitRequested = true
                        advanceStep()
                    }
                }
            } else {
                primaryButton("Next") {
                    advanceStep()
                }
            }
        }
    }

    // MARK: - Step 6: Birth Date (tag 6)

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

    // MARK: - Step 7: Biological Sex (tag 7)

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
        .accessibilityLabel(label)
        .accessibilityAddTraits(biologicalSex == sex ? .isSelected : [])
    }

    // MARK: - Step 8: Smoking (tag 8)

    @ViewBuilder
    private var smokingStep: some View {
        stepContainer {
            stepIcon("smoke")
            stepTitle("Do you smoke?")
            stepDescription("Smoking is the single largest modifiable risk factor for life expectancy.")

            Spacer()

            VStack(spacing: 12) {
                smokingCard("Never", status: .never, impact: String(format: "%+.0fy", DeathClockEngine.smokingImpact(.never)))
                smokingCard("Former", status: .former, impact: String(format: "%+.0fy", DeathClockEngine.smokingImpact(.former)))
                smokingCard("Current", status: .current, impact: String(format: "%+.0fy", DeathClockEngine.smokingImpact(.current)))
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
        .accessibilityLabel("\(label) smoker, \(impact) years impact")
        .accessibilityAddTraits(smokingStatus == status ? .isSelected : [])
    }

    // MARK: - Step 9: Exercise (tag 9)

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
                .accessibilityLabel("Exercise minutes per week")
                .accessibilityValue("\(Int(exerciseMinutes)) minutes")

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

    // MARK: - Step 10: Sleep (tag 10)

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
                .accessibilityLabel("Sleep hours per night")
                .accessibilityValue(String(format: "%.1f hours", sleepHours))

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

    // MARK: - Step 11: Diet & Stress (tag 11)

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

    // MARK: - Step 12: Results (tag 12)

    @ViewBuilder
    private var resultsStep: some View {
        stepContainer {
            stepIcon("clock")
            stepTitle("Your Life Expectancy")

            if let result = lifeExpectancyResult {
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

                    // Projected life expectancy date
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

    // MARK: - Step 2: Apex Goal

    @ViewBuilder
    private var apexGoalStep: some View {
        stepContainer {
            stepIcon("crown.fill")
            stepTitle("Your North Star")
            stepDescription("Your single biggest life purpose — the thing everything else serves. Broad, lifelong, no end date. Examples: \u{201C}Live healthy for as long as possible\u{201D}, \u{201C}Leave a lasting creative legacy\u{201D}, \u{201C}Raise a loving resilient family.\u{201D}")

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your North Star")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    TextField("e.g. Leave a lasting creative legacy", text: $apexGoalTitle)
                        .textFieldStyle(.plain)
                        .submitLabel(.next)
                        .onSubmit { advanceStep() }
                        .padding(12)
                        .background(Color.bgInput)
                        .cornerRadius(10)
                        .foregroundColor(.textPrimary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes (optional)")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    TextField("How would you know you're living it?", text: $apexGoalNotes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Color.bgInput)
                        .cornerRadius(10)
                        .foregroundColor(.textPrimary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Category")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    // A 3-column chip grid — a segmented Picker truncates
                    // 6 full-word labels like "Creative" and "Financial" at
                    // iPhone widths. Chips wrap and keep the full label.
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        ForEach(GoalCategory.allCases, id: \.self) { cat in
                            Button {
                                // Tap to select, tap again to clear — no
                                // preselected category nudges the user.
                                apexGoalCategory = (apexGoalCategory == cat) ? nil : cat
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: cat.icon)
                                        .font(.caption2)
                                    Text(cat.label)
                                        .font(.caption).fontWeight(.medium)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(apexGoalCategory == cat ? Color.accentColor.opacity(0.2) : Color.bgInput)
                                .foregroundColor(apexGoalCategory == cat ? .accentColor : .textSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(apexGoalCategory == cat ? Color.accentColor : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Always "Next" — whether or not the user filled anything in.
            // Empty-state handling happens in `saveAndDismiss()`.
            primaryButton("Next") {
                advanceStep()
            }
        }
    }

    // MARK: - Step 3: First Reflection

    /// Seed the Reflections journal with an initial reflection on the new
    /// North Star. The user answers one question and rates their current
    /// alignment. This gives the app a baseline to compare future reviews
    /// against, and teaches the user what a reflection feels like before
    /// they encounter the weekly review loop.
    private var firstReflectionStep: some View {
        stepContainer {
            stepIcon("bubble.left.and.bubble.right.fill")
            stepTitle("Your first reflection")
            stepDescription("MortalLoom's core loop is reflecting on how well you\u{2019}re living your North Star — not just logging tasks. Let\u{2019}s start with one honest answer.")

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why does this matter to you?")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("The real reason — not the tidy one", text: $firstReflectionAnswer, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(Color.bgInput)
                        .cornerRadius(10)
                        .foregroundColor(.textPrimary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Right now, how aligned does your life feel with this?")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("\(Int(firstReflectionRating))/10")
                            .font(.title3).fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.accentColor)
                        Spacer()
                        Text(AlignmentScale.label(for: Int(firstReflectionRating)))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Slider(value: $firstReflectionRating, in: 1...10, step: 1)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Historical bug: this step was once the final step, so its button
            // called `saveAndDismiss()`. When the flow was reordered to put the
            // lifestyle steps after reflection, the button action was never
            // updated — causing every new user to skip the entire longevity
            // profile collection. Reflection is now step 3 of 13; the final
            // save happens on the Results step.
            primaryButton("Next") {
                advanceStep()
            }
        }
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
            // Without fixedSize, SwiftUI prefers horizontal truncation when
            // space is tight — e.g. "matters more..." becomes "matt..." on
            // the LEV step. Lock vertical growth instead.
            .fixedSize(horizontal: false, vertical: true)
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
        let nextStep = min(currentStep + 1, totalSteps - 1)
        // Results step (now step 12) renders the calculated life expectancy,
        // so compute it when transitioning into it. Done here rather than in
        // a task on the step itself so the result is ready the moment the
        // step animates in.
        if nextStep == 12 {
            let birthDateStr = DateFormatting.dateString(birthDate)
            let lifestyle = LifestyleData(
                smokingStatus: smokingStatus,
                exerciseMinutesPerWeek: Int(exerciseMinutes),
                sleepHoursPerNight: sleepHours,
                dietQuality: dietQuality,
                stressLevel: stressLevel,
                bmi: nil
            )
            lifeExpectancyResult = DeathClockEngine.calculate(birthDateStr: birthDateStr, sex: biologicalSex, lifestyle: lifestyle)
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = nextStep
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

        let trimmedTitle = apexGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Apex goals are lifetime purposes: no targetDate, lifetime horizon.
        // Seed with the first reflection as an initial check-in so the
        // Reflections journal has content from day one.
        var apexGoal: Goal? = nil
        if !trimmedTitle.isEmpty {
            var g = Goal(
                title: trimmedTitle,
                notes: apexGoalNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                targetDate: nil,
                checkInIntervalDays: 14,
                status: .active,
                priority: .high,
                horizon: .lifetime,
                category: apexGoalCategory,
                goalType: .apex
            )
            let trimmedReflection = firstReflectionAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            // Seed the reflections journal if the user typed an answer.
            // The rating defaults to 5 (neutral "Mixed") so even users who
            // never touched the slider get a reasonable baseline.
            if !trimmedReflection.isEmpty {
                g.checkIns.append(GoalCheckIn(
                    progressPct: 0,
                    note: trimmedReflection,
                    alignmentRating: Int(firstReflectionRating),
                    blockers: [],
                    commitments: [],
                    promptAnswered: "Why does this matter to you?"
                ))
            }
            apexGoal = g
        }

        // Turn on the weekly review reminder by default — the entire goal
        // alignment loop hinges on it, and users who missed onboarding
        // notifications would otherwise never see a review prompt.
        UserDefaults.standard.set(true, forKey: NotificationService.weeklyReviewEnabledKey)

        Task { @MainActor in
            await DataStore.shared.updateProfile(profile)
            if let apexGoal {
                await DataStore.shared.addGoal(apexGoal)
            }
            UserDefaults.standard.set(true, forKey: AppConstants.hasCompletedOnboardingKey)
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
            isPresented = false
        }
    }
}
