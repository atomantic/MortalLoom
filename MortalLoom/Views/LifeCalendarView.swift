import SwiftUI

struct LifeCalendarView: View {
    @State private var data: AppData = .empty
    @State private var deathClock: DeathClockEngine.DeathClockResult?
    @State private var levDeathClock: DeathClockEngine.DeathClockResult?
    @State private var countdownMode: CountdownMode = .standard
    // Default to years on first launch — the 80-year weeks grid is cool but
    // nearly-empty for users with no scheduled goals. Years gives them a
    // sense of the span without the scale shock. Persisted so the user's
    // explicit preference sticks across launches.
    @AppStorage("calendar.viewMode") private var viewMode: ViewMode = .years
    @State private var showLEVExplainer = false
    @State private var goalMarkers: [GoalMarker] = []
    @State private var goalWeekSet: Set<Int> = []
    @State private var projectedWeekSet: Set<Int> = []
    @State private var tooltipInfo: CellTooltip?
    @State private var isLoaded = false
    /// When false, lived weeks/months/years are rendered the same as future
    /// (empty) cells — the grid becomes a forward-looking planning surface.
    /// Defaults to hiding past time so goals stand out against remaining years.
    @State private var showLived: Bool = false

    private struct CellTooltip: Equatable {
        let age: Int
        let dateRange: String
        let goals: [String]
        let projectedGoals: [String]
        let isMilestone: Bool
        let isCurrentPeriod: Bool
    }

    private enum ViewMode: String, CaseIterable {
        case years = "Years"
        case months = "Months"
        case weeks = "Weeks"
    }

    private var activeDC: DeathClockEngine.DeathClockResult? {
        if countdownMode == .lev, let levDC = levDeathClock { return levDC }
        return deathClock
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
        activeDC?.ageYears ?? 0
    }

    private var totalWeeks: Int {
        guard let dc = activeDC else { return 80 * 52 }
        return Int(dc.lifeExpectancy.total * 52)
    }

    private var totalMonths: Int {
        guard let dc = activeDC else { return 80 * 12 }
        return Int(dc.lifeExpectancy.total * 12)
    }

    private var lifeExpectancyYears: Int {
        guard let dc = activeDC else { return 80 }
        return Int(dc.lifeExpectancy.total.rounded())
    }

    private var daysRemaining: Int {
        guard let dc = activeDC else { return 0 }
        let diff = dc.deathDate.timeIntervalSince(Date())
        return max(0, Int(diff / 86400))
    }

    private var weeksRemaining: Int {
        max(0, totalWeeks - currentWeek)
    }

    private var monthsRemaining: Int {
        guard let dc = activeDC else { return 0 }
        return max(0, Int(dc.yearsRemaining * 12))
    }

    private var yearsRemaining: Double {
        activeDC?.yearsRemaining ?? 0
    }

    private var saturdaysRemaining: Int {
        weeksRemaining
    }

    private var awakeDaysRemaining: Int {
        Int(Double(daysRemaining) * 16.0 / 24.0)
    }

    private static let milestoneAges = [0, 18, 30, 40, 50, 60, 70, 80, 90, 100]

    @State private var goalsByYear: [Int: [GoalMarker]] = [:]
    @State private var goalsByMonth: [Int: [GoalMarker]] = [:]
    @State private var goalsByWeek: [Int: [GoalMarker]] = [:]

    private var goalMonthSet: Set<Int> {
        Set(goalMarkers.filter { !$0.isProjected }.map { Int(Double($0.weekIndex) / 4.33) })
    }
    private var projectedMonthSet: Set<Int> {
        Set(goalMarkers.filter { $0.isProjected }.map { Int(Double($0.weekIndex) / 4.33) })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 80)
                } else if deathClock != nil && birthDate != nil {
                    statsGrid
                    viewModePicker
                    switch viewMode {
                    case .years: yearsGrid
                    case .months: monthsGrid
                    case .weeks: weeksGrid
                    }
                    if !goalMarkers.isEmpty {
                        goalMarkersList
                    }
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color.bg)
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
            Task { await loadData() }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        let loaded = await DataStore.shared.getData()
        data = loaded
        recalculate()
        isLoaded = true
    }

    private func recalculate() {
        guard let birthDateStr = data.profile.birthDate else {
            deathClock = nil
            levDeathClock = nil
            goalMarkers = []
            return
        }
        countdownMode = data.profile.countdownMode
        let dc = DeathClockEngine.calculate(
            birthDateStr: birthDateStr,
            sex: data.profile.biologicalSex,
            lifestyle: data.profile.lifestyle,
            genome: data.genomeScanRecord,
            locationProfile: data.profile.locationProfile,
            healthMetrics: data.healthMetrics
        )
        deathClock = dc
        levDeathClock = dc.flatMap { DeathClockEngine.calculateLEVResult(standardResult: $0, birthDateStr: birthDateStr, levTargetAge: data.profile.levTargetAge) }

        guard let birth = DeathClockEngine.dateFromString(birthDateStr) else {
            goalMarkers = []
            return
        }

        let cogDate = GoalEngine.cognitiveDeadline(from: dc)
        let markers = GoalEngine.goalMarkers(
            goals: data.goals, birthDate: birth,
            deathDate: dc?.deathDate, healthyCognitiveDate: cogDate
        )
        goalMarkers = markers
        goalWeekSet = Set(markers.filter { !$0.isProjected }.map(\.weekIndex))
        projectedWeekSet = Set(markers.filter { $0.isProjected }.map(\.weekIndex))

        var byYear: [Int: [GoalMarker]] = [:]
        var byMonth: [Int: [GoalMarker]] = [:]
        var byWeek: [Int: [GoalMarker]] = [:]
        for m in markers {
            byYear[m.weekIndex / 52, default: []].append(m)
            byMonth[Int(Double(m.weekIndex) / 4.33), default: []].append(m)
            byWeek[m.weekIndex, default: []].append(m)
        }
        goalsByYear = byYear
        goalsByMonth = byMonth
        goalsByWeek = byWeek
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
            Text("Add your birth date in the Lifestyle page (or re-run the setup wizard) to see your life as a grid of weeks.")
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
                Image(systemName: countdownMode == .lev ? "bolt.shield.fill" : "hourglass")
                    .foregroundColor(countdownMode == .lev ? .success : .accentColor)
                    .font(.title3)
                Text("There's still time!")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            if levDeathClock != nil {
                HStack(spacing: 8) {
                    Picker("Countdown", selection: $countdownMode) {
                        ForEach(CountdownMode.allCases, id: \.self) { mode in
                            Text(mode.pickerLabel).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: countdownMode) { _, newMode in
                        data.profile.countdownMode = newMode
                        Task { await DataStore.shared.save(data) }
                        NotificationCenter.default.post(name: .profileDidChange, object: nil)
                    }

                    Button {
                        showLEVExplainer = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("What is LEV?")
                    .popover(isPresented: $showLEVExplainer, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Longevity Escape Velocity")
                                .font(.subheadline).fontWeight(.semibold)
                            Text(CountdownMode.standardBlurb)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(CountdownMode.levBlurb)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(width: 280)
                        .presentationCompactAdaptation(.popover)
                    }
                }
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label) remaining")
    }

    // MARK: - View Mode Picker

    @ViewBuilder
    private var viewModePicker: some View {
        VStack(spacing: 8) {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $showLived) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("Show lived time")
                        .font(.caption)
                }
                .foregroundColor(.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    // MARK: - Years Grid

    @ViewBuilder
    private var yearsGrid: some View {
        let cols = 10
        let goalYears = Set(goalWeekSet.map { $0 / 52 })
        let projectedYears = Set(projectedWeekSet.map { $0 / 52 })

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Goal Timeline in Years")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Text(showLived
                 ? "\(currentAgeYear) years lived, \(String(format: "%.1f", yearsRemaining)) remaining."
                 : "\(String(format: "%.1f", yearsRemaining)) years remaining. Plan your goals below.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            yearMonthLegend

            tooltipOverlay

            let rows = (lifeExpectancyYears + cols - 1) / cols
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols), spacing: 4) {
                ForEach(0..<(rows * cols), id: \.self) { i in
                    if i < lifeExpectancyYears {
                        let isCurrent = i == currentAgeYear
                        let isSpent = i < currentAgeYear
                        let isMilestone = Self.milestoneAges.contains(i)
                        let isGoalTarget = goalYears.contains(i)
                        let isProjected = projectedYears.contains(i)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(yearCellColor(index: i, isCurrent: isCurrent, isSpent: isSpent, isMilestone: isMilestone, isGoalTarget: isGoalTarget, isProjected: isProjected))
                            .frame(height: 24)
                            .overlay {
                                if isGoalTarget || isProjected {
                                    Image(systemName: "target")
                                        .font(.system(size: 8))
                                        .foregroundColor(.white)
                                } else if i % 10 == 0 || isCurrent {
                                    Text("\(i)")
                                        .font(.system(size: 8, weight: isCurrent ? .bold : .regular))
                                        .foregroundColor(isCurrent ? .white : .textMuted)
                                }
                            }
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    let tip = tooltipForYear(i)
                                    tooltipInfo = tooltipInfo == tip ? nil : tip
                                }
                            }
                            #if os(macOS)
                            .onHover { hovering in
                                if hovering { tooltipInfo = tooltipForYear(i) }
                            }
                            #endif
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Life in years grid: \(currentAgeYear) years lived, \(String(format: "%.1f", yearsRemaining)) remaining of \(lifeExpectancyYears) total")
    }

    private func yearCellColor(index: Int, isCurrent: Bool, isSpent: Bool, isMilestone: Bool, isGoalTarget: Bool, isProjected: Bool) -> Color {
        if isCurrent { return .accentColor }
        if isGoalTarget { return .teal }
        if isProjected { return .teal.opacity(0.5) }
        if isMilestone && isSpent && showLived { return .purple.opacity(0.5) }
        if isMilestone && !isSpent { return .purple.opacity(0.3) }
        if isSpent && showLived { return .textPrimary.opacity(0.25) }
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
                Text("Goal Timeline in Months")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Text(showLived
                 ? "\(currentMonth) months lived, \(monthsRemaining) remaining."
                 : "\(monthsRemaining) months remaining. Plan your goals below.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            yearMonthLegend

            tooltipOverlay

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
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let y = value.location.y - spacing
                                let x = value.location.x - labelWidth - 4
                                let year = Int(y / (cellSize + spacing))
                                let month = Int(x / (cellSize + spacing))
                                guard year >= 0, year < lifeExpectancyYears, month >= 0, month < 12 else {
                                    tooltipInfo = nil
                                    return
                                }
                                let monthIndex = year * 12 + month
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    let tip = tooltipForMonth(monthIndex)
                                    tooltipInfo = tooltipInfo == tip ? nil : tip
                                }
                            }
                    )
                }
            }
            .frame(height: monthGridHeight)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Life in months grid: \(currentMonth) months lived, \(monthsRemaining) remaining")
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
        let goalShading: GraphicsContext.Shading = .color(.teal)
        let projectedShading: GraphicsContext.Shading = .color(.teal.opacity(0.5))

        let milestoneMonths = Set(Self.milestoneAges.map { $0 * 12 })
        // Convert week indices to month indices (approximate: week / 4.33)
        let goalMonthIndices = goalMonthSet
        let projectedMonthIndices = projectedMonthSet

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
                } else if goalMonthIndices.contains(monthIndex) {
                    let expand: CGFloat = cellSize * 0.1
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    context.fill(Path(roundedRect: expandedRect, cornerRadius: cornerRadius), with: goalShading)
                } else if projectedMonthIndices.contains(monthIndex) {
                    let expand: CGFloat = cellSize * 0.1
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    context.fill(Path(roundedRect: expandedRect, cornerRadius: cornerRadius), with: projectedShading)
                } else if milestoneMonths.contains(monthIndex) && (showLived || monthIndex >= currentMonth) {
                    context.fill(path, with: milestoneShading)
                } else if monthIndex < currentMonth && showLived {
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
                Text("Goal Timeline in Weeks")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            Text(showLived
                 ? "Each square = 1 week. \(formatLargeNumber(currentWeek)) weeks lived, \(formatLargeNumber(weeksRemaining)) remaining."
                 : "Each square = 1 week remaining. \(formatLargeNumber(weeksRemaining)) weeks to plan.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            weeksLegend

            tooltipOverlay

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
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let y = value.location.y - spacing
                                let x = value.location.x - labelWidth - 4
                                let year = Int(y / (cellSize + spacing))
                                let week = Int(x / (cellSize + spacing))
                                guard year >= 0, year < lifeExpectancyYears, week >= 0, week < 52 else {
                                    tooltipInfo = nil
                                    return
                                }
                                let weekIndex = year * 52 + week
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    let tip = tooltipForWeek(weekIndex)
                                    tooltipInfo = tooltipInfo == tip ? nil : tip
                                }
                            }
                    )
                }
            }
            .frame(height: weeksGridHeight)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Life in weeks grid: \(currentWeek) weeks lived, \(weeksRemaining) remaining")
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
            if showLived {
                legendItem(color: .textPrimary.opacity(0.25), label: "Lived")
            }
            legendItem(color: .accentColor, label: "Now")
            legendItem(color: .clear, borderColor: .cardBorder.opacity(0.2), label: "Future")
            legendItem(color: .purple.opacity(0.4), label: "Milestone")
            if !goalMarkers.isEmpty {
                legendItem(color: .teal, label: "Goal")
            }
        }
        .font(.system(size: 9))
    }

    @ViewBuilder
    private var weeksLegend: some View {
        HStack(spacing: 12) {
            if showLived {
                legendItem(color: .textPrimary.opacity(0.25), label: "Lived")
            }
            legendItem(color: .accentColor, label: "This Week")
            legendItem(color: .clear, borderColor: .cardBorder.opacity(0.2), label: "Future")
            legendItem(color: .purple.opacity(0.5), label: "Milestone")
            if !goalMarkers.isEmpty {
                legendItem(color: .teal, label: "Goal")
            }
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
        let goalShading: GraphicsContext.Shading = .color(.teal)
        let projectedShading: GraphicsContext.Shading = .color(.teal.opacity(0.5))

        let milestoneWeeks = Set(Self.milestoneAges.map { $0 * 52 })
        let goalWeeks = goalWeekSet
        let projectedWeeks = projectedWeekSet

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
                } else if goalWeeks.contains(weekIndex) {
                    let expand: CGFloat = cellSize * 0.2
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    context.fill(Path(roundedRect: expandedRect, cornerRadius: cornerRadius * 1.2), with: goalShading)
                } else if projectedWeeks.contains(weekIndex) {
                    let expand: CGFloat = cellSize * 0.15
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    context.fill(Path(roundedRect: expandedRect, cornerRadius: cornerRadius * 1.1), with: projectedShading)
                } else if milestoneWeeks.contains(weekIndex) && (showLived || weekIndex >= currentWeek) {
                    context.fill(path, with: milestoneShading)
                } else if weekIndex == totalWeeks {
                    context.fill(path, with: deathShading)
                } else if weekIndex < currentWeek && showLived {
                    context.fill(path, with: spentShading)
                } else {
                    context.stroke(path, with: futureStrokeShading, lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: - Goal Markers List

    @ViewBuilder
    private var goalMarkersList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "GOALS ON YOUR TIMELINE")
            ForEach(goalMarkers.sorted(by: { $0.weekIndex < $1.weekIndex }), id: \.title) { marker in
                HStack(spacing: 8) {
                    Circle()
                        .fill(marker.isProjected ? Color.teal.opacity(0.5) : Color.teal)
                        .frame(width: 8, height: 8)
                    Text(marker.title)
                        .font(.caption)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let birth = birthDate {
                        let targetDate = Calendar.current.date(byAdding: .day, value: marker.weekIndex * 7, to: birth)
                        if let d = targetDate {
                            Text(marker.isProjected ? "projected" : "target")
                                .font(.system(size: 9))
                                .foregroundColor(.textMuted)
                            Text(DateFormatting.dateString(d))
                                .font(.caption2).monospacedDigit()
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Tooltip

    @ViewBuilder
    private var tooltipOverlay: some View {
        if let tip = tooltipInfo {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tip.isCurrentPeriod ? "You are here" : "Age \(tip.age)")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(tip.isCurrentPeriod ? .accentColor : .textPrimary)
                    Spacer()
                    Text(tip.dateRange)
                        .font(.caption2).monospacedDigit()
                        .foregroundColor(.textSecondary)
                    Button { tooltipInfo = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                if tip.isMilestone {
                    Text("Milestone Age")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }

                if !tip.goals.isEmpty {
                    ForEach(tip.goals, id: \.self) { g in
                        HStack(spacing: 4) {
                            Circle().fill(Color.teal).frame(width: 6, height: 6)
                            Text(g).font(.caption2).foregroundColor(.textPrimary).lineLimit(1)
                            Text("target").font(.system(size: 8)).foregroundColor(.textMuted)
                        }
                    }
                }

                if !tip.projectedGoals.isEmpty {
                    ForEach(tip.projectedGoals, id: \.self) { g in
                        HStack(spacing: 4) {
                            Circle().fill(Color.teal.opacity(0.5)).frame(width: 6, height: 6)
                            Text(g).font(.caption2).foregroundColor(.textPrimary).lineLimit(1)
                            Text("projected").font(.system(size: 8)).foregroundColor(.textMuted)
                        }
                    }
                }

                if tip.goals.isEmpty && tip.projectedGoals.isEmpty && !tip.isMilestone && !tip.isCurrentPeriod {
                    Text("No goals in this period")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            }
            .padding(10)
            .cardStyle(fill: .bgCard, border: .accentColor.opacity(0.3))
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    private func tooltipForYear(_ year: Int) -> CellTooltip {
        let markers = goalsByYear[year] ?? []
        let dateRange = yearDateRange(year)
        return CellTooltip(
            age: year,
            dateRange: dateRange,
            goals: markers.filter { !$0.isProjected }.map(\.title),
            projectedGoals: markers.filter { $0.isProjected }.map(\.title),
            isMilestone: Self.milestoneAges.contains(year),
            isCurrentPeriod: year == currentAgeYear
        )
    }

    private func tooltipForMonth(_ monthIndex: Int) -> CellTooltip {
        let year = monthIndex / 12
        let month = monthIndex % 12
        let markers = goalsByMonth[monthIndex] ?? []
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let monthLabel = monthNames[month]
        let dateRange: String
        if let birth = birthDate {
            let date = Calendar.current.date(byAdding: .month, value: monthIndex, to: birth) ?? Date()
            dateRange = "\(monthLabel) (age \(year)) \u{2022} \(DateFormatting.dateString(date))"
        } else {
            dateRange = "\(monthLabel), age \(year)"
        }
        return CellTooltip(
            age: year,
            dateRange: dateRange,
            goals: markers.filter { !$0.isProjected }.map(\.title),
            projectedGoals: markers.filter { $0.isProjected }.map(\.title),
            isMilestone: Self.milestoneAges.contains(year) && month == 0,
            isCurrentPeriod: monthIndex == currentMonth
        )
    }

    private func tooltipForWeek(_ weekIndex: Int) -> CellTooltip {
        let year = weekIndex / 52
        let markers = goalsByWeek[weekIndex] ?? []
        let dateRange: String
        if let birth = birthDate {
            let date = Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: birth) ?? Date()
            dateRange = "Week \(weekIndex % 52 + 1), age \(year) \u{2022} \(DateFormatting.dateString(date))"
        } else {
            dateRange = "Week \(weekIndex % 52 + 1), age \(year)"
        }
        return CellTooltip(
            age: year,
            dateRange: dateRange,
            goals: markers.filter { !$0.isProjected }.map(\.title),
            projectedGoals: markers.filter { $0.isProjected }.map(\.title),
            isMilestone: Self.milestoneAges.contains(year) && weekIndex % 52 == 0,
            isCurrentPeriod: weekIndex == currentWeek
        )
    }

    private func yearDateRange(_ year: Int) -> String {
        guard let birth = birthDate else { return "Age \(year)" }
        let start = Calendar.current.date(byAdding: .year, value: year, to: birth) ?? Date()
        return DateFormatting.dateString(start)
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ n: Int) -> String {
        DateFormatting.formatLargeNumber(n)
    }
}
