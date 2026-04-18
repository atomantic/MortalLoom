import SwiftUI

// MARK: - WeeklyReviewSheet

/// The weekly review is the core substantive moment of the app's loop.
/// A 5-minute guided flow that walks the user through 4 steps:
///
/// 1. **Review** — show last week's check-in/completion activity and how
///    alignment moved.
/// 2. **Reflect** — pick one guided prompt and answer it.
/// 3. **Rate** — self-rate current alignment 1-10.
/// 4. **Commit** — list 1-3 commitments for next week.
///
/// On finish, a reflection-shaped `GoalCheckIn` is appended to the user's
/// North Star goal (or to the active life pillar if no apex is set), and
/// the last-review date is stamped in UserDefaults so the Overview CTA
/// knows when to surface the review again.
struct WeeklyReviewSheet: View {
    let apex: Goal?
    let allGoals: [Goal]
    let habits: [Habit]
    let onSave: (Goal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .review
    @State private var selectedPrompt: String = ""
    @State private var answer: String = ""
    // Default 5 ("Mixed") — don't assume the user feels "mostly aligned"
    // before they've even touched the slider.
    @State private var alignmentRating: Double = 5
    @State private var commitmentsText: String = ""

    enum Step: Int, CaseIterable {
        case review, reflect, rate, commit

        var title: String {
            switch self {
            case .review: "This week at a glance"
            case .reflect: "One question to sit with"
            case .rate: "How aligned are you feeling?"
            case .commit: "What will you commit to?"
            }
        }

        var stepNumber: Int { rawValue + 1 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        stepHeader
                        Divider()
                        switch step {
                        case .review: reviewStep
                        case .reflect: reflectStep
                        case .rate: rateStep
                        case .commit: commitStep
                        }
                    }
                    .padding()
                }
                Divider()
                navigationFooter
            }
            .background(Color.bg)
            .navigationTitle("Weekly Review")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .macSheetFrame()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
            .onAppear {
                if selectedPrompt.isEmpty {
                    selectedPrompt = ReflectionPrompts.nextPrompt(for: apex)
                }
            }
        }
    }

    // MARK: Progress / header

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.bgInput)
                    .frame(height: 4)
                Rectangle()
                    .fill(LinearGradient.proBrand)
                    .frame(width: geo.size.width * CGFloat(step.rawValue + 1) / CGFloat(Step.allCases.count), height: 4)
            }
        }
        .frame(height: 4)
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step \(step.stepNumber) of \(Step.allCases.count)")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.accentColor)
                .tracking(1)
                .textCase(.uppercase)
            Text(step.title)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Review step

    @ViewBuilder
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let apex {
                Text(apex.title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }

            let activity = weekActivity()
            statRow(icon: "pencil.and.list.clipboard", label: "Check-ins", value: "\(activity.checkIns.count)")
            if !activity.checkIns.isEmpty {
                itemList(activity.checkIns, color: .accentColor)
            }
            statRow(icon: "checkmark.seal.fill", label: "Goals completed", value: "\(activity.completions.count)")
            if !activity.completions.isEmpty {
                itemList(activity.completions, color: .success)
            }
            statRow(icon: "repeat.circle.fill", label: "Habit completions", value: "\(activity.habitHits)")

            if let score = currentAlignment() {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current alignment")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    HStack {
                        Text("\(Int(score))%")
                            .font(.largeTitle).fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                }
            }

            Text("Take a breath. This step is just to notice. Nothing to do yet.")
                .font(.caption).italic()
                .foregroundColor(.textMuted)
                .padding(.top, 6)
        }
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
            Spacer()
            Text(value)
                .font(.headline).monospacedDigit()
                .foregroundColor(.textPrimary)
        }
    }

    /// Bulleted list of goal titles under a stat row — turns "3 check-ins"
    /// from a number into a narrative the user actually remembers.
    private func itemList(_ titles: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(titles, id: \.self) { title in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding(.leading, 34)
        .padding(.bottom, 2)
    }

    // MARK: Reflect step

    @ViewBuilder
    private var reflectStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedPrompt)
                .font(.headline)
                .foregroundColor(.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(10)

            TextField("Your answer — don't overthink it", text: $answer, axis: .vertical)
                .lineLimit(4...10)
                .padding(12)
                .background(Color.bgInput)
                .cornerRadius(10)

            Button {
                rotatePrompt()
            } label: {
                Label("Give me a different question", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
    }

    private func rotatePrompt() {
        selectedPrompt = ReflectionPrompts.nextPrompt(for: apex, excluding: selectedPrompt)
    }

    // MARK: Rate step

    @ViewBuilder
    private var rateStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("On a scale of 1 to 10, how aligned has your life been with your goals this week?")
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .center, spacing: 8) {
                Text("\(Int(alignmentRating))")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.accentColor)
                Text(AlignmentScale.label(for: Int(alignmentRating)))
                    .font(.headline)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity)

            Slider(value: $alignmentRating, in: 1...10, step: 1)
        }
    }

    // MARK: Commit step

    @ViewBuilder
    private var commitStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lastCommitments = previousCommitments(), !lastCommitments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last week you committed to…")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    ForEach(lastCommitments, id: \.self) { c in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrowtriangle.forward.fill")
                                .font(.caption2)
                                .foregroundColor(.textMuted)
                            Text(c)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                }
                .padding(10)
                .background(Color.bgInput)
                .cornerRadius(10)
            }

            Text("What will you commit to this week to move your goals forward? One line per commitment.")
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("e.g. Two 45-minute writing sessions\ne.g. No alcohol weekdays", text: $commitmentsText, axis: .vertical)
                .lineLimit(4...8)
                .padding(12)
                .background(Color.bgInput)
                .cornerRadius(10)

            Text("Keep it small. Three commitments you actually do beats ten you don't.")
                .font(.caption).italic()
                .foregroundColor(.textMuted)
        }
    }

    /// The most-recent commitments list attached to the apex — shown on
    /// the Commit step so the user can see what they promised last time
    /// before promising anything new.
    private func previousCommitments() -> [String]? {
        guard let apex else { return nil }
        return apex.checkIns.last(where: { !$0.commitments.isEmpty })?.commitments
    }

    // MARK: Footer

    private var navigationFooter: some View {
        HStack(spacing: 12) {
            if step.rawValue > 0 {
                Button {
                    withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .review }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.textSecondary)
            }
            Spacer()
            Button {
                if step == .commit {
                    finish()
                } else {
                    withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .commit }
                }
            } label: {
                HStack {
                    Text(step == .commit ? "Finish" : "Next")
                        .fontWeight(.semibold)
                    Image(systemName: step == .commit ? "checkmark.circle.fill" : "chevron.right")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(LinearGradient.proBrand)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(nextDisabled)
        }
        .padding()
    }

    /// Next/Finish is gated on having input at each meaningful step:
    /// Reflect needs an answer, Commit needs at least one line, Finish
    /// needs an apex to attach to (otherwise the reflection has no home).
    private var nextDisabled: Bool {
        switch step {
        case .review:
            return false
        case .reflect:
            return answer.trimmingCharacters(in: .whitespaces).isEmpty
        case .rate:
            return false
        case .commit:
            let hasCommitments = commitmentsText
                .split(separator: "\n")
                .contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return !hasCommitments || apex == nil
        }
    }

    // MARK: Finish

    private func finish() {
        // Guarded by `nextDisabled`, but keep a defensive check so a future
        // code path can't silently drop reflections on the floor.
        guard let apex else { return }

        let commitmentsList = commitmentsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var updated = apex
        updated.checkIns.append(GoalCheckIn(
            progressPct: 0,
            note: answer.trimmingCharacters(in: .whitespaces),
            alignmentRating: Int(alignmentRating),
            blockers: [],
            commitments: commitmentsList,
            promptAnswered: selectedPrompt
        ))
        UserDefaults.standard.set(DateFormatting.todayString(), forKey: WeeklyReview.lastDateKey)
        onSave(updated)
        dismiss()
    }

    // MARK: Computed metrics

    /// Reflective activity in the last 7 days — returns the actual check-in
    /// and completion titles (not just counts) so the review step can render
    /// them as a narrative the user remembers.
    private func weekActivity() -> (checkIns: [String], completions: [String], habitHits: Int) {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else {
            return ([], [], 0)
        }
        let weekAgoStr = DateFormatting.dateString(weekAgo)

        var checkIns: [String] = []
        var completions: [String] = []
        for g in allGoals {
            if g.checkIns.contains(where: { $0.date >= weekAgoStr }) {
                checkIns.append(g.title)
            }
            if g.status == .completed, let completed = g.completedDate, completed >= weekAgoStr {
                completions.append(g.title)
            }
        }
        let habitHits = habits
            .filter { $0.isActive }
            .flatMap { $0.completions }
            .filter { $0.date >= weekAgoStr }
            .count
        return (checkIns, completions, habitHits)
    }

    private func currentAlignment() -> Double? {
        guard let apex else { return nil }
        return GoalEngine.alignmentScore(for: apex, in: allGoals)
    }
}

// MARK: - WeeklyReview helpers

enum WeeklyReview {
    static let lastDateKey = "lastWeeklyReviewDate"
    static let intervalKey = "weeklyReviewIntervalDays"

    /// True when the user is due for a weekly review. Default cadence is 7
    /// days; if they've never done one, they're always due. Callers can
    /// override via UserDefaults at `intervalKey`.
    static var isDue: Bool {
        let raw = UserDefaults.standard.integer(forKey: intervalKey)
        let interval = raw > 0 ? raw : 7
        guard let last = UserDefaults.standard.string(forKey: lastDateKey),
              let lastDate = DateFormatting.dateFromString(last) else {
            return true
        }
        let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return days >= interval
    }

    static var lastReviewDate: String? {
        UserDefaults.standard.string(forKey: lastDateKey)
    }
}
