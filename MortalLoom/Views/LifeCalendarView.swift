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
    @State private var showAwakeDaysExplainer = false
    @State private var goalMarkers: [GoalMarker] = []
    @State private var goalWeekSet: Set<Int> = []
    @State private var projectedWeekSet: Set<Int> = []
    // Month-bucket indices, cached here instead of recomputed in the view body.
    // The months grid read these inside a GeometryReader, so the previous
    // computed-property versions rebuilt both Sets over every goal marker on
    // each render pass (#31). Populated by recalculate().
    @State private var goalMonthSet: Set<Int> = []
    @State private var projectedMonthSet: Set<Int> = []
    @State private var tooltipInfo: CellTooltip?
    @State private var isLoaded = false
    /// When false, lived weeks/months/years are rendered the same as future
    /// (empty) cells — the grid becomes a forward-looking planning surface.
    /// Defaults to hiding past time so goals stand out against remaining years.
    @State private var showLived: Bool = false

    private struct TooltipGoal: Equatable, Hashable {
        let title: String
        let parentPath: String
    }

    private struct CellTooltip: Equatable {
        let age: Int
        let dateRange: String
        let goals: [TooltipGoal]
        let projectedGoals: [TooltipGoal]
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

    /// First age-year to render in the grids. When Show Lived Time is off
    /// we skip past every fully-lived year so the calendar starts at the
    /// user's current age instead of at birth — reclaims vertical space.
    private var startAgeYear: Int {
        showLived ? 0 : currentAgeYear
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
        await recalculate()
        isLoaded = true
    }

    /// Holds the off-main recalculation output. Returned from a detached task,
    /// so every field is `Sendable` (the engine result types already are).
    private struct CalendarRecalc: Sendable {
        var deathClock: DeathClockEngine.DeathClockResult?
        var levDeathClock: DeathClockEngine.DeathClockResult?
        var markers: [GoalMarker] = []
        var goalWeekSet: Set<Int> = []
        var projectedWeekSet: Set<Int> = []
        var goalMonthSet: Set<Int> = []
        var projectedMonthSet: Set<Int> = []
        var goalsByYear: [Int: [GoalMarker]] = [:]
        var goalsByMonth: [Int: [GoalMarker]] = [:]
        var goalsByWeek: [Int: [GoalMarker]] = [:]
    }

    private func recalculate() async {
        guard let birthDateStr = data.profile.birthDate else {
            deathClock = nil
            levDeathClock = nil
            goalMarkers = []
            goalWeekSet = []
            projectedWeekSet = []
            goalMonthSet = []
            projectedMonthSet = []
            goalsByYear = [:]
            goalsByMonth = [:]
            goalsByWeek = [:]
            return
        }
        countdownMode = data.profile.countdownMode

        // Run the mortality + goal-marker engines off the main actor (mirrors the
        // genome-scan pattern) so reloads — including the double-fire this issue
        // also addresses — don't block rendering (#31). Capture the value-type
        // inputs up front; results are published back on the main actor below.
        let profile = data.profile
        let goals = data.goals
        let genome = data.genomeScanRecord
        let healthMetrics = data.healthMetrics
        let result = await Task.detached(priority: .utility) {
            let dc = DeathClockEngine.calculate(
                birthDateStr: birthDateStr,
                sex: profile.biologicalSex,
                lifestyle: profile.lifestyle,
                genome: genome,
                locationProfile: profile.locationProfile,
                socioeconomic: profile.socioeconomic,
                healthMetrics: healthMetrics
            )
            let lev = dc.flatMap {
                DeathClockEngine.calculateLEVResult(standardResult: $0, birthDateStr: birthDateStr, levTargetAge: profile.levTargetAge)
            }
            guard let birth = DeathClockEngine.dateFromString(birthDateStr) else {
                return CalendarRecalc(deathClock: dc, levDeathClock: lev)
            }
            let cogDate = GoalEngine.cognitiveDeadline(from: dc)
            let markers = GoalEngine.goalMarkers(
                goals: goals, birthDate: birth,
                deathDate: dc?.deathDate, healthyCognitiveDate: cogDate
            )
            var byYear: [Int: [GoalMarker]] = [:]
            var byMonth: [Int: [GoalMarker]] = [:]
            var byWeek: [Int: [GoalMarker]] = [:]
            for m in markers {
                byYear[m.weekIndex / 52, default: []].append(m)
                byMonth[Int(Double(m.weekIndex) / 4.33), default: []].append(m)
                byWeek[m.weekIndex, default: []].append(m)
            }
            return CalendarRecalc(
                deathClock: dc,
                levDeathClock: lev,
                markers: markers,
                goalWeekSet: Set(markers.filter { !$0.isProjected }.map(\.weekIndex)),
                projectedWeekSet: Set(markers.filter { $0.isProjected }.map(\.weekIndex)),
                goalMonthSet: Set(markers.filter { !$0.isProjected }.map { Int(Double($0.weekIndex) / 4.33) }),
                projectedMonthSet: Set(markers.filter { $0.isProjected }.map { Int(Double($0.weekIndex) / 4.33) }),
                goalsByYear: byYear,
                goalsByMonth: byMonth,
                goalsByWeek: byWeek
            )
        }.value

        deathClock = result.deathClock
        levDeathClock = result.levDeathClock
        goalMarkers = result.markers
        goalWeekSet = result.goalWeekSet
        projectedWeekSet = result.projectedWeekSet
        goalMonthSet = result.goalMonthSet
        projectedMonthSet = result.projectedMonthSet
        goalsByYear = result.goalsByYear
        goalsByMonth = result.goalsByMonth
        goalsByWeek = result.goalsByWeek
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
                        Task { await DataStore.shared.updateCountdownMode(newMode) }
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
                statCard(
                    value: formatLargeNumber(awakeDaysRemaining),
                    label: "Awake Days",
                    icon: "eye.fill",
                    color: .blue
                )
                .overlay(alignment: .topTrailing) {
                    Button {
                        showAwakeDaysExplainer = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("What are Awake Days?")
                    .popover(isPresented: $showAwakeDaysExplainer, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Awake Days")
                                .font(.subheadline).fontWeight(.semibold)
                            Text("Roughly how many waking days you have left, after subtracting time spent sleeping. Based on your lifestyle sleep-hours answer: 8 hours of sleep a night means ⅓ of your remaining life is spent asleep.")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(width: 260)
                        .presentationCompactAdaptation(.popover)
                    }
                }
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

            let startYear = startAgeYear
            let renderedYears = max(0, lifeExpectancyYears - startYear)
            let rows = (renderedYears + cols - 1) / cols
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols), spacing: 4) {
                ForEach(0..<(rows * cols), id: \.self) { idx in
                    let i = idx + startYear
                    if idx < renderedYears {
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
                                } else if (i % 10 == 0 || isCurrent) && !(isSpent && !showLived) {
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
        .overlay(alignment: .top) { tooltipOverlay }
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
        // When Show Lived Time is off, don't render a box for spent years.
        if isSpent { return .clear }
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

            GeometryReader { geo in
                let availableWidth = geo.size.width
                let labelWidth: CGFloat = 28
                let gridWidth = availableWidth - labelWidth - 4
                let layout = monthsLayout(gridWidth: gridWidth)
                let cellSize = layout.cellSize
                let spacing = layout.spacing
                let monthsPerRow = layout.monthsPerRow
                let startMonth = startAgeYear * 12
                let totalMonthCells = max(0, totalMonths - startMonth)
                let totalRows = (totalMonthCells + monthsPerRow - 1) / monthsPerRow
                let totalHeight = CGFloat(totalRows) * (cellSize + spacing) + spacing
                // Hoisted out of Canvas body so the Set<Int> allocation
                // doesn't rebuild on every repaint.
                let goalIndices = goalMonthSet
                let projectedIndices = projectedMonthSet

                ScrollView(.vertical, showsIndicators: true) {
                    Canvas { context, size in
                        drawMonthsGrid(
                            context: &context,
                            labelWidth: labelWidth,
                            cellSize: cellSize,
                            spacing: spacing,
                            monthsPerRow: monthsPerRow,
                            startMonth: startMonth,
                            goalIndices: goalIndices,
                            projectedIndices: projectedIndices
                        )
                    }
                    .frame(width: availableWidth, height: totalHeight)
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let y = value.location.y - spacing
                                let x = value.location.x - labelWidth - 4
                                let row = Int(y / (cellSize + spacing))
                                let col = Int(x / (cellSize + spacing))
                                guard row >= 0, col >= 0, col < monthsPerRow else {
                                    tooltipInfo = nil
                                    return
                                }
                                let monthIndex = row * monthsPerRow + col + startMonth
                                guard monthIndex < totalMonths else {
                                    tooltipInfo = nil
                                    return
                                }
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
        .overlay(alignment: .top) { tooltipOverlay }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Life in months grid: \(currentMonth) months lived, \(monthsRemaining) remaining")
    }

    private var monthGridHeight: CGFloat {
        let years = max(1, lifeExpectancyYears - startAgeYear)
        #if os(macOS)
        // Hug content up to a cap so short lifespans don't leave a giant
        // empty canvas. ~24pt per row matches the default macOS cell stride
        // and the ScrollView handles overflow past the cap.
        return min(CGFloat(years) * 24 + 20, 720)
        #else
        return min(CGFloat(years * 16 + 20), 600)
        #endif
    }

    #if os(macOS)
    // Each candidate must divide 12 evenly so every row spans a whole
    // number of years and the year-start label math stays clean.
    private static let macMonthRowCandidates: [Int] = [36, 24, 12]
    private static let macMonthTargetCellSize: CGFloat = 24
    private static let macMonthMinCellSize: CGFloat = 8
    private static let macMonthMaxCellSize: CGFloat = 48
    private static let macMonthSpacing: CGFloat = 3
    #endif

    /// Picks a months-per-row density based on available width, targeting
    /// `macMonthTargetCellSize` cells. Wider windows flow into 24 or 36
    /// months per row (2 or 3 years on the same line) so the grid is
    /// denser without requiring the user to scroll a long vertical strip.
    private func monthsLayout(gridWidth: CGFloat) -> (monthsPerRow: Int, cellSize: CGFloat, spacing: CGFloat) {
        #if os(macOS)
        let spacing = Self.macMonthSpacing
        let target = Self.macMonthTargetCellSize
        let perRow = Self.macMonthRowCandidates.first {
            gridWidth >= CGFloat($0) * target + CGFloat($0 - 1) * spacing
        } ?? 12
        let rawCell = (gridWidth - CGFloat(perRow - 1) * spacing) / CGFloat(perRow)
        let cellSize = max(Self.macMonthMinCellSize, min(Self.macMonthMaxCellSize, rawCell))
        return (perRow, cellSize, spacing)
        #else
        let cellSize = max(4, min(18, gridWidth / 12 - 2))
        return (12, cellSize, 2)
        #endif
    }

    private func drawMonthsGrid(
        context: inout GraphicsContext,
        labelWidth: CGFloat,
        cellSize: CGFloat,
        spacing: CGFloat,
        monthsPerRow: Int,
        startMonth: Int,
        goalIndices: Set<Int>,
        projectedIndices: Set<Int>
    ) {
        let cornerRadius = max(1, cellSize * 0.2)
        let spentShading: GraphicsContext.Shading = .color(.textPrimary.opacity(0.25))
        let currentShading: GraphicsContext.Shading = .color(.accentColor)
        // Future cells need a visible bed in dark mode — a thin stroke at
        // 20% opacity disappears against near-black backgrounds. Use a
        // faint fill so every cell is legible.
        let futureFillShading: GraphicsContext.Shading = .color(.textPrimary.opacity(0.08))
        let futureStrokeShading: GraphicsContext.Shading = .color(.textPrimary.opacity(0.18))
        let milestoneShading: GraphicsContext.Shading = .color(.purple.opacity(0.5))
        let goalShading: GraphicsContext.Shading = .color(.teal)
        let projectedShading: GraphicsContext.Shading = .color(.teal.opacity(0.5))

        let milestoneMonths = Set(Self.milestoneAges.map { $0 * 12 })

        let totalMonthCells = max(0, totalMonths - startMonth)
        let totalRows = (totalMonthCells + monthsPerRow - 1) / monthsPerRow
        // Label every row; the row-to-year formula produces stride
        // `monthsPerRow / 12` so labels read 0, 2, 4… at 24/row or 0, 3, 6…
        // at 36/row. When startMonth > 0 (Show Lived Time off) labels start
        // at the current age instead of 0.
        let labelFontSize = max(7, min(10, cellSize * 0.45))

        for row in 0..<totalRows {
            let y = CGFloat(row) * (cellSize + spacing) + spacing
            let firstMonthInRow = row * monthsPerRow + startMonth
            let yearOfRow = firstMonthInRow / 12
            let text = Text("\(yearOfRow)")
                .font(.system(size: labelFontSize))
                .foregroundColor(.textMuted)
            let resolvedText = context.resolve(text)
            context.draw(resolvedText, at: CGPoint(x: labelWidth / 2, y: y + cellSize / 2), anchor: .center)

            for col in 0..<monthsPerRow {
                let monthIndex = row * monthsPerRow + col + startMonth
                if monthIndex >= totalMonths { break }

                let x = labelWidth + 4 + CGFloat(col) * (cellSize + spacing)
                let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                if monthIndex == currentMonth {
                    let expand: CGFloat = cellSize * 0.15
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    context.fill(Path(roundedRect: expandedRect, cornerRadius: cornerRadius * 1.2), with: currentShading)
                } else if goalIndices.contains(monthIndex) {
                    let expand: CGFloat = cellSize * 0.1
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    context.fill(Path(roundedRect: expandedRect, cornerRadius: cornerRadius), with: goalShading)
                } else if projectedIndices.contains(monthIndex) {
                    let expand: CGFloat = cellSize * 0.1
                    let expandedRect = CGRect(x: x - expand / 2, y: y - expand / 2, width: cellSize + expand, height: cellSize + expand)
                    context.fill(Path(roundedRect: expandedRect, cornerRadius: cornerRadius), with: projectedShading)
                } else if milestoneMonths.contains(monthIndex) && (showLived || monthIndex >= currentMonth) {
                    context.fill(path, with: milestoneShading)
                } else if monthIndex < currentMonth && showLived {
                    context.fill(path, with: spentShading)
                } else if monthIndex >= currentMonth && monthIndex < totalMonths {
                    context.fill(path, with: futureFillShading)
                    context.stroke(path, with: futureStrokeShading, lineWidth: 0.5)
                }
                // When showLived is false and monthIndex < currentMonth,
                // no clause matches — cell renders empty.
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

            GeometryReader { geo in
                let availableWidth = geo.size.width
                let labelWidth: CGFloat = 28
                let gridWidth = availableWidth - labelWidth - 4
                #if os(macOS)
                let cellSize = max(4, min(16, gridWidth / 52 - 1))
                #else
                let cellSize = max(3, min(7, gridWidth / 52))
                #endif
                let spacing: CGFloat = max(0.5, cellSize * 0.15)
                let renderedYears = max(0, lifeExpectancyYears - startAgeYear)
                let totalHeight = CGFloat(renderedYears) * (cellSize + spacing) + spacing

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
                                let visualYear = Int(y / (cellSize + spacing))
                                let week = Int(x / (cellSize + spacing))
                                let year = visualYear + startAgeYear
                                guard year >= startAgeYear, year < lifeExpectancyYears, week >= 0, week < 52 else {
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
        .overlay(alignment: .top) { tooltipOverlay }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Life in weeks grid: \(currentWeek) weeks lived, \(weeksRemaining) remaining")
    }

    private var weeksGridHeight: CGFloat {
        let years = max(1, lifeExpectancyYears - startAgeYear)
        #if os(macOS)
        // Larger macOS cells (up to 16pt) — ~18pt per year accounts for
        // cell + ~2pt spacing.
        return min(CGFloat(years * 18 + 20), 1400)
        #else
        return min(CGFloat(years * 8 + 20), 600)
        #endif
    }

    @ViewBuilder
    private var yearMonthLegend: some View {
        HStack(spacing: 12) {
            if showLived {
                legendItem(color: .textPrimary.opacity(0.25), label: "Lived")
            }
            legendItem(color: .accentColor, label: "Now")
            legendItem(color: .textPrimary.opacity(0.08), borderColor: .textPrimary.opacity(0.18), label: "Future")
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
            legendItem(color: .textPrimary.opacity(0.08), borderColor: .textPrimary.opacity(0.18), label: "Future")
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
        // Fill + stroke so every cell is visible in dark mode. See months
        // grid for rationale.
        let futureFillShading: GraphicsContext.Shading = .color(.textPrimary.opacity(0.08))
        let futureStrokeShading: GraphicsContext.Shading = .color(.textPrimary.opacity(0.18))
        let milestoneShading: GraphicsContext.Shading = .color(.purple.opacity(0.5))
        let deathShading: GraphicsContext.Shading = .color(.danger.opacity(0.7))
        let goalShading: GraphicsContext.Shading = .color(.teal)
        let projectedShading: GraphicsContext.Shading = .color(.teal.opacity(0.5))

        let milestoneWeeks = Set(Self.milestoneAges.map { $0 * 52 })
        let goalWeeks = goalWeekSet
        let projectedWeeks = projectedWeekSet

        let firstYear = startAgeYear
        for year in firstYear..<lifeExpectancyYears {
            let y = CGFloat(year - firstYear) * (cellSize + spacing) + spacing

            if year % 10 == 0 || year == lifeExpectancyYears - 1 || year == firstYear {
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
                } else if weekIndex >= currentWeek {
                    context.fill(path, with: futureFillShading)
                    context.stroke(path, with: futureStrokeShading, lineWidth: 0.5)
                }
                // When showLived is false and weekIndex < currentWeek,
                // no clause matches — cell renders empty.
            }
        }
    }

    // MARK: - Goal Markers List

    @ViewBuilder
    private var goalMarkersList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "GOALS ON YOUR TIMELINE")
            // Composite id so two goals that share a title (e.g. "Finish
            // design" under different pillars) both render instead of being
            // deduped by ForEach.
            ForEach(goalMarkers.sorted(by: { $0.weekIndex < $1.weekIndex }),
                    id: \.compositeId) { marker in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(marker.isProjected ? Color.teal.opacity(0.5) : Color.teal)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(marker.title)
                            .font(.caption)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        if !marker.parentPath.isEmpty {
                            Text(marker.parentPath)
                                .font(.system(size: 9))
                                .foregroundColor(.textMuted)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
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
                        tooltipGoalRow(goal: g, dotColor: .teal, label: "target")
                    }
                }

                if !tip.projectedGoals.isEmpty {
                    ForEach(tip.projectedGoals, id: \.self) { g in
                        tooltipGoalRow(goal: g, dotColor: .teal.opacity(0.5), label: "projected")
                    }
                }

                if tip.goals.isEmpty && tip.projectedGoals.isEmpty && !tip.isMilestone && !tip.isCurrentPeriod {
                    Text("No goals in this period")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            }
            .padding(10)
            .frame(maxWidth: 340)
            .cardStyle(fill: .bgCard, border: .accentColor.opacity(0.4))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.top, 56)
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .allowsHitTesting(true)
        }
    }

    /// Renders a single goal row inside the life-calendar tooltip. Shows the
    /// title on the first line and — if the goal has a parent chain — the
    /// path ("Apex › Sub-apex › Parent") on a muted second line so repeated
    /// sub-goal titles can be told apart at a glance.
    @ViewBuilder
    private func tooltipGoalRow(goal: TooltipGoal, dotColor: Color, label: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(goal.title)
                        .font(.caption2)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundColor(.textMuted)
                }
                if !goal.parentPath.isEmpty {
                    Text(goal.parentPath)
                        .font(.system(size: 9))
                        .foregroundColor(.textMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
    }

    private func tooltipForYear(_ year: Int) -> CellTooltip {
        let markers = goalsByYear[year] ?? []
        let dateRange = yearDateRange(year)
        return CellTooltip(
            age: year,
            dateRange: dateRange,
            goals: markers.filter { !$0.isProjected }.map { TooltipGoal(title: $0.title, parentPath: $0.parentPath) },
            projectedGoals: markers.filter { $0.isProjected }.map { TooltipGoal(title: $0.title, parentPath: $0.parentPath) },
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
            goals: markers.filter { !$0.isProjected }.map { TooltipGoal(title: $0.title, parentPath: $0.parentPath) },
            projectedGoals: markers.filter { $0.isProjected }.map { TooltipGoal(title: $0.title, parentPath: $0.parentPath) },
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
            goals: markers.filter { !$0.isProjected }.map { TooltipGoal(title: $0.title, parentPath: $0.parentPath) },
            projectedGoals: markers.filter { $0.isProjected }.map { TooltipGoal(title: $0.title, parentPath: $0.parentPath) },
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
