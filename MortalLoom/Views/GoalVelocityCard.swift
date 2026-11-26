import SwiftUI
import Charts

struct GoalVelocityCard: View {
    let series: [GoalVelocityEngine.Series]
    @State private var selectedGoal: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "GOAL VELOCITY")
            if let goal = series.first(where: { $0.id == selectedGoal }) ?? series.first {
                if series.count > 1 {
                    Picker("Goal", selection: Binding(get: { goal.id }, set: { selectedGoal = $0 })) {
                        ForEach(series) { item in
                            Text(item.title).tag(item.id)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text(goal.title)
                        .font(.subheadline.weight(.semibold))
                }
                velocityChart(goal.intervals)
                if let recent = goal.intervals.last {
                    Text("Latest pace: \(formattedRate(recent.pointsPerWeek)) percentage points per week")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                Text("Pace between check-ins, not a forecast. Negative values mean reported progress went down.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            } else {
                Label("Log progress on two different days for a standard goal to see its pace.",
                      systemImage: "chart.bar.xaxis")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func velocityChart(_ intervals: [GoalVelocityEngine.Interval]) -> some View {
        Chart {
            RuleMark(y: .value("No change", 0))
                .foregroundStyle(Color.textMuted.opacity(0.5))
                .accessibilityHidden(true)
            ForEach(intervals) { interval in
                BarMark(
                    x: .value("Check-in date", interval.end, unit: .day),
                    y: .value("Points per week", interval.pointsPerWeek),
                    width: .fixed(10)
                )
                .foregroundStyle(interval.pointsPerWeek < 0 ? Color.orange : Color.accentColor)
                .accessibilityLabel("\(interval.start.formatted(date: .abbreviated, time: .omitted)) to \(interval.end.formatted(date: .abbreviated, time: .omitted))")
                .accessibilityValue("\(formattedRate(interval.pointsPerWeek)) percentage points per week")
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartYAxisLabel("Points/week")
        .frame(height: 160)
    }

    private func formattedRate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    }
}
