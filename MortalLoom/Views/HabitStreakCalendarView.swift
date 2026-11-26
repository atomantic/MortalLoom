import SwiftUI

struct HabitStreakCalendarView: View {
    let periods: [HabitStreakCalendar.Period]
    let cadence: HabitCadencePeriod

    private var isWeekly: Bool { cadence == .weekly }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: isWeekly ? 4 : 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let first = periods.first, let last = periods.last {
                Text("\(rangeDate(first.start)) – \(rangeDate(last.start))")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(periods) { period in
                    cell(period)
                }
            }
            Text(isWeekly
                 ? "Each square is a week starting Monday. ✓ Target met · • Logged · – No log"
                 : "Each square is a day. ✓ Target met · • Logged · – No log")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Habit streak calendar")
    }

    private func rangeDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func cell(_ period: HabitStreakCalendar.Period) -> some View {
        let marker = !period.isTracked ? " " : period.meetsTarget ? "✓" : period.count > 0 ? "•" : "–"
        let color: Color = !period.isTracked ? Color.textMuted.opacity(0.06)
            : period.meetsTarget ? Color.success.opacity(0.28)
            : period.count > 0 ? Color.accentColor.opacity(0.22) : Color.bgInput

        return VStack(spacing: 1) {
            Text(isWeekly ? period.start.formatted(.dateTime.month(.narrow).day()) : period.start.formatted(.dateTime.day()))
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(marker)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(color, in: RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isWeekly ? "Week of \(rangeDate(period.start))" : rangeDate(period.start))
        .accessibilityValue(period.isTracked
                            ? "\(period.count) of \(period.target) logged\(period.meetsTarget ? ", target met" : "")"
                            : "Not tracked")
        .help("\(rangeDate(period.start)): \(period.isTracked ? "\(period.count) / \(period.target)" : "Not tracked")")
    }
}
