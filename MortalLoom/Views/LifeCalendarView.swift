import SwiftUI

struct LifeCalendarView: View {
    @State private var data: AppData = .empty
    @State private var deathClock: DeathClockEngine.DeathClockResult?
    @State private var viewMode: ViewMode = .weeks

    private enum ViewMode: String, CaseIterable {
        case years = "Years"
        case months = "Months"
        case weeks = "Weeks"
    }

    private var birthDate: Date? {
        guard let str = data.profile.birthDate else { return nil }
        return DeathClockEngine.dateFromString(str)
    }

    private var currentWeek: Int {
        guard let birth = birthDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: birth, to: Date()).day ?? 0
        return max(0, days / 7)
    }

    private var currentMonth: Int {
        guard let birth = birthDate else { return 0 }
        let months = Calendar.current.dateComponents([.month], from: birth, to: Date()).month ?? 0
        return max(0, months)
    }

    private var currentAgeYear: Int {
        deathClock?.ageYears ?? 0
    }

    private var totalWeeks: Int {
        guard let dc = deathClock else { return 80 * 52 }
        return Int(dc.lifeExpectancy.total * 52)
    }

    private var totalMonths: Int {
        guard let dc = deathClock else { return 80 * 12 }
        return Int(dc.lifeExpectancy.total * 12)
    }

    private var lifeExpectancyYears: Int {
        guard let dc = deathClock else { return 80 }
        return Int(dc.lifeExpectancy.total.rounded())
    }

    private var daysRemaining: Int {
        guard let dc = deathClock else { return 0 }
        let diff = dc.deathDate.timeIntervalSince(Date())
        return max(0, Int(diff / 86400))
    }

    private var weeksRemaining: Int {
        max(0, totalWeeks - currentWeek)
    }

    private var monthsRemaining: Int {
        guard let dc = deathClock else { return 0 }
        return max(0, Int(dc.yearsRemaining * 12))
    }

    private var yearsRemaining: Double {
        deathClock?.yearsRemaining ?? 0
    }

    private var saturdaysRemaining: Int {
        weeksRemaining
    }

    private var awakeDaysRemaining: Int {
        Int(Double(daysRemaining) * 16.0 / 24.0)
    }

    private static let milestoneAges = [0, 18, 30, 40, 50, 60, 70, 80, 90, 100]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if deathClock != nil && birthDate != nil {
                    statsGrid
                    viewModePicker
                    switch viewMode {
                    case .years: yearsGrid
                    case .months: monthsGrid
                    case .weeks: weeksGrid
                    }
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color.bg)
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
            Task { await loadData() }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        let loaded = await DataStore.shared.getData()
        data = loaded
        recalculate()
    }

    private func recalculate() {
        guard let birthDateStr = data.profile.birthDate else {
            deathClock = nil
            return
        }
        deathClock = DeathClockEngine.calculate(
            birthDateStr: birthDateStr,
            sex: data.profile.biologicalSex,
            lifestyle: data.profile.lifestyle
        )
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundColor(.textMuted)
            Text("Life Calendar")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text("Configure your birth date in Settings to see your life as a grid of weeks.")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 60)
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hourglass")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Time Remaining")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                statCard(value: String(format: "%.1f", yearsRemaining), label: "Years", icon: "calendar.circle", color: .accentColor)
                statCard(value: "\(monthsRemaining)", label: "Months", icon: "calendar", color: .purple)
                statCard(value: formatLargeNumber(weeksRemaining), label: "Weeks", icon: "calendar.day.timeline.left", color: .teal)
                statCard(value: formatLargeNumber(daysRemaining), label: "Days", icon: "sun.max.fill", color: .orange)
                statCard(value: formatLargeNumber(saturdaysRemaining), label: "Saturdays", icon: "star.fill", color: .yellow)
                statCard(value: formatLargeNumber(awakeDaysRemaining), label: "Awake Days", icon: "eye.fill", color: .blue)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    @ViewBuilder
    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            Text(value)
                .font(.headline).fontWeight(.bold).monospacedDigit()
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.bgInput.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - View Mode Picker

    @ViewBuilder
    private var viewModePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Years Grid

    @ViewBuilder
    private var yearsGrid: some View {
        let cols = 10
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Your Life in Years")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Text("\(currentAgeYear) years lived, \(String(format: "%.1f", yearsRemaining)) remaining.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            yearMonthLegend

            let rows = (lifeExpectancyYears + cols - 1) / cols
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols), spacing: 4) {
                ForEach(0..<(rows * cols), id: \.self) { i in
                    if i < lifeExpectancyYears {
                        let isCurrent = i == currentAgeYear
                        let isSpent = i < currentAgeYear
                        let isMilestone = Self.milestoneAges.contains(i)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(yearCellColor(index: i, isCurrent: isCurrent, isSpent: isSpent, isMilestone: isMilestone))
                            .frame(height: 24)
                            .overlay {
                                if i % 10 == 0 || isCurrent {
                                    Text("\(i)")
                                        .font(.system(size: 8, weight: isCurrent ? .bold : .regular))
                                        .foregroundColor(isCurrent ? .white : .textMuted)
                                }
                            }
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func yearCellColor(index: Int, isCurrent: Bool, isSpent: Bool, isMilestone: Bool) -> Color {
        if isCurrent { return .accentColor }
        if isMilestone && isSpent { return .purple.opacity(0.5) }
        if isMilestone { return .purple.opacity(0.3) }
        if isSpent { return .textPrimary.opacity(0.25) }
        return .cardBorder.opacity(0.15)
    }

    // MARK: - Months Grid

    @ViewBuilder
    private var monthsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Your Life in Months")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Text("\(currentMonth) months lived, \(monthsRemaining) remaining.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            yearMonthLegend

            GeometryReader { geo in
                let availableWidth = geo.size.width
                let labelWidth: CGFloat = 28
                let gridWidth = availableWidth - labelWidth - 4
                let cellSize = max(4, min(18, gridWidth / 12 - 2))
                let spacing: CGFloat = 2
                let totalHeight = CGFloat(lifeExpectancyYears) * (cellSize + spacing) + spacing

                ScrollView(.vertical, showsIndicators: true) {
                    Canvas { context, size in
                        drawMonthsGrid(context: &context, labelWidth: labelWidth, cellSize: cellSize, spacing: spacing)
                    }
                    .frame(width: availableWidth, height: totalHeight)
                }
            }
            .frame(height: monthGridHeight)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var monthGridHeight: CGFloat {
        #if os(macOS)
        return min(CGFloat(lifeExpectancyYears * 16 + 20), 700)
        #else
        return min(CGFloat(lifeExpectancyYears * 16 + 20), 600)
        #endif
    }

    private func drawMonthsGrid(
        context: inout GraphicsContext,
        labelWidth: CGFloat,
        cellSize: CGFloat,
        spacing: CGFloat
    ) {
        let cornerRadius = max(1, cellSize * 0.2)
        let spentShading: GraphicsContext.Shading = .color(.textPrimary.opacity(0.25))
        let currentShading: GraphicsContext.Shading = .color(.accentColor)
        let futureStrokeShading: GraphicsContext.Shading = .color(.cardBorder.opacity(0.2))
        let milestoneShading: GraphicsContext.Shading = .color(.purple.opacity(0.5))

        let milestoneMonths = Set(Self.milestoneAges.map { $0 * 12 })

        for year in 0..<lifeExpectancyYears {
            let y = CGFloat(year) * (cellSize + spacing) + spacing

            if year % 10 == 0 || year == lifeExpectancyYears - 1 {
                let text = Text("\(year)")
                    .font(.system(size: max(7, min(10, cellSize * 0.7))))
                    .foregroundColor(.textMuted)
                let resolvedText = context.resolve(text)
                context.draw(resolvedText, at: CGPoint(x: labelWidth / 2, y: y + cellSize / 2), anchor: .center)
            }

            for month in 0..<12 {
                let monthIndex = year * 12 + month
                let x = labelWidth + 4 + CGFloat(month) * (cellSize + spacing)
                let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                if monthIndex == currentMonth {
                    let expand: CGFloat = cellSize * 0.15
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    context.fill(Path(roundedRect: expandedRect, cornerRadius: cornerRadius * 1.2), with: currentShading)
                } else if milestoneMonths.contains(monthIndex) {
                    context.fill(path, with: milestoneShading)
                } else if monthIndex < currentMonth {
                    context.fill(path, with: spentShading)
                } else if monthIndex < totalMonths {
                    context.stroke(path, with: futureStrokeShading, lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: - Weeks Grid

    @ViewBuilder
    private var weeksGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Your Life in Weeks")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Text("Each square = 1 week. \(formatLargeNumber(currentWeek)) weeks lived, \(formatLargeNumber(weeksRemaining)) remaining.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            weeksLegend

            GeometryReader { geo in
                let availableWidth = geo.size.width
                let labelWidth: CGFloat = 28
                let gridWidth = availableWidth - labelWidth - 4
                let cellSize = max(3, min(7, gridWidth / 52))
                let spacing: CGFloat = max(0.5, cellSize * 0.15)
                let totalHeight = CGFloat(lifeExpectancyYears) * (cellSize + spacing) + spacing

                ScrollView(.vertical, showsIndicators: true) {
                    Canvas { context, size in
                        drawWeeksGrid(context: &context, labelWidth: labelWidth, cellSize: cellSize, spacing: spacing)
                    }
                    .frame(width: availableWidth, height: totalHeight)
                }
            }
            .frame(height: weeksGridHeight)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var weeksGridHeight: CGFloat {
        #if os(macOS)
        return min(CGFloat(lifeExpectancyYears * 8 + 20), 700)
        #else
        return min(CGFloat(lifeExpectancyYears * 8 + 20), 600)
        #endif
    }

    @ViewBuilder
    private var yearMonthLegend: some View {
        HStack(spacing: 12) {
            legendItem(color: .textPrimary.opacity(0.25), label: "Lived")
            legendItem(color: .accentColor, label: "Now")
            legendItem(color: .clear, borderColor: .cardBorder.opacity(0.2), label: "Future")
            legendItem(color: .purple.opacity(0.4), label: "Milestone")
        }
        .font(.system(size: 9))
    }

    @ViewBuilder
    private var weeksLegend: some View {
        HStack(spacing: 12) {
            legendItem(color: .textPrimary.opacity(0.25), label: "Lived")
            legendItem(color: .accentColor, label: "This Week")
            legendItem(color: .clear, borderColor: .cardBorder.opacity(0.2), label: "Future")
            legendItem(color: .purple.opacity(0.5), label: "Milestone")
        }
        .font(.system(size: 9))
    }

    @ViewBuilder
    private func legendItem(color: Color, borderColor: Color? = nil, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5)
                        .stroke(borderColor ?? .clear, lineWidth: 0.5)
                )
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Canvas Drawing (Weeks)

    private func drawWeeksGrid(
        context: inout GraphicsContext,
        labelWidth: CGFloat,
        cellSize: CGFloat,
        spacing: CGFloat
    ) {
        let cornerRadius = max(1, cellSize * 0.2)

        let spentShading: GraphicsContext.Shading = .color(.textPrimary.opacity(0.25))
        let currentShading: GraphicsContext.Shading = .color(.accentColor)
        let futureStrokeShading: GraphicsContext.Shading = .color(.cardBorder.opacity(0.2))
        let milestoneShading: GraphicsContext.Shading = .color(.purple.opacity(0.5))
        let deathShading: GraphicsContext.Shading = .color(.danger.opacity(0.7))

        let milestoneWeeks = Set(Self.milestoneAges.map { $0 * 52 })

        for year in 0..<lifeExpectancyYears {
            let y = CGFloat(year) * (cellSize + spacing) + spacing

            if year % 10 == 0 || year == lifeExpectancyYears - 1 {
                let text = Text("\(year)")
                    .font(.system(size: max(6, min(9, cellSize * 1.4))))
                    .foregroundColor(.textMuted)
                let resolvedText = context.resolve(text)
                context.draw(resolvedText, at: CGPoint(x: labelWidth / 2, y: y + cellSize / 2), anchor: .center)
            }

            for week in 0..<52 {
                let weekIndex = year * 52 + week
                let x = labelWidth + 4 + CGFloat(week) * (cellSize + spacing)

                let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                if weekIndex == currentWeek {
                    let expand: CGFloat = cellSize * 0.25
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    let expandedPath = Path(roundedRect: expandedRect, cornerRadius: cornerRadius * 1.3)
                    context.fill(expandedPath, with: currentShading)
                } else if milestoneWeeks.contains(weekIndex) {
                    context.fill(path, with: milestoneShading)
                } else if weekIndex == totalWeeks {
                    context.fill(path, with: deathShading)
                } else if weekIndex < currentWeek {
                    context.fill(path, with: spentShading)
                } else {
                    context.stroke(path, with: futureStrokeShading, lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ n: Int) -> String {
        DateFormatting.formatLargeNumber(n)
    }
}
