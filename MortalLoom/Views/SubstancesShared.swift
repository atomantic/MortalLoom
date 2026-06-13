import SwiftUI
import Charts

// MARK: - Substance Tab Enum

/// Identifies which built-in substance/sauna tracker is being shown. Used by
/// `HabitsPage` to drive the embedded `SubstancesView` when the user picks a
/// built-in tab from the Habits page picker.
enum SubstanceTab: String, CaseIterable {
    case alcohol = "Alcohol"
    case nicotine = "Nicotine"
    case sauna = "Sauna"
}

// MARK: - Volume Unit

enum VolumeUnit: String, CaseIterable {
    case oz = "oz"
    case ml = "ml"

    var toOz: Double {
        switch self {
        case .oz: 1.0
        case .ml: 1.0 / 29.5735
        }
    }
}

// MARK: - Alcohol Risk Color

extension AlcoholRisk {
    var color: Color {
        switch self {
        case .low: .success
        case .moderate: .warning
        case .high: .danger
        }
    }
}

// MARK: - Date Helpers

func substanceTodayString() -> String {
    DateFormatting.todayString()
}

func substanceDateString(daysAgo: Int) -> String {
    DateFormatting.dateString(daysAgo: daysAgo)
}

func substanceDisplayDate(_ dateStr: String) -> String {
    DateFormatting.displayDate(dateStr)
}

func last30DayStrings() -> [String] {
    (0..<30).reversed().map { substanceDateString(daysAgo: $0) }
}

// MARK: - Chart Data Point

struct DailyAmount: Identifiable {
    let id: String
    let date: String
    let amount: Double

    init(date: String, amount: Double) {
        self.id = date
        self.date = date
        self.amount = amount
    }
}

// MARK: - Stat Math Helpers

/// Mean of the values, or nil for an empty list (so callers can show "no data").
func substanceAverage(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
}

/// Percent change of `comparison` relative to `baseline`, or nil when the
/// baseline is missing/zero (avoids a divide-by-zero and a meaningless %).
func substancePctDifference(_ baseline: Double?, _ comparison: Double?) -> Double? {
    guard let b = baseline, let c = comparison, b > 0 else { return nil }
    return (b - c) / b * 100
}

// MARK: - Shared Substance UI Components

/// "Manage Presets" link shared by the alcohol / nicotine / sauna quick-add cards.
@MainActor
func managePresetsLink(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 4) {
            Image(systemName: "slider.horizontal.3")
            Text("Manage Presets")
        }
        .font(.caption)
        .foregroundColor(.accentColor)
    }
    .buttonStyle(.plain)
}

/// One labelled stat in a substance stats bar.
@MainActor
func substanceStatItem(label: String, value: String, valueColor: Color = .textPrimary) -> some View {
    VStack(spacing: 2) {
        Text(label)
            .font(.caption2)
            .foregroundColor(.textMuted)
        Text(value)
            .font(.subheadline.bold())
            .foregroundColor(valueColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label): \(value)")
}

/// One labelled column in a correlation summary (drinking vs sober, sauna vs rest, …).
func sleepStatColumn(label: String, value: String, color: Color) -> some View {
    VStack(spacing: 2) {
        Text(label)
            .font(.caption2)
            .foregroundColor(.textMuted)
        Text(value)
            .font(.subheadline.bold())
            .foregroundColor(color)
    }
    .frame(maxWidth: .infinity)
}

// MARK: - Quick-Add Chip Reordering

/// Reorder a preset list after a quick-add chip drag-and-drop. `draggedID` is
/// the dragged preset's UUID string (the drag payload); `targetID` is the chip
/// it was dropped on. Dropping left-of-origin lands the item before the target,
/// right-of-origin lands it after — so every slot (including the end) is
/// reachable. Returns nil for a no-op drop (same slot, or an unknown id from a
/// stray external drag) so callers skip the write.
func reorderedByDrag<T: Identifiable>(_ presets: [T], draggedID: String, targetID: T.ID) -> [T]? where T.ID == UUID {
    guard let from = presets.firstIndex(where: { $0.id.uuidString == draggedID }),
          let to = presets.firstIndex(where: { $0.id == targetID }),
          from != to else { return nil }
    var reordered = presets
    let moved = reordered.remove(at: from)
    reordered.insert(moved, at: to)
    return reordered
}

/// Move the preset identified by `id` by `offset` positions (negative = earlier).
/// Returns nil when the id isn't present or the move would fall off either end,
/// so callers skip the write. Backs the assistive-tech "Move earlier/later" chip
/// actions, which give VoiceOver / Switch-Control users a non-drag path to the
/// same reordering.
func presetMoved<T: Identifiable>(_ presets: [T], id: T.ID, offset: Int) -> [T]? where T.ID == UUID {
    guard let from = presets.firstIndex(where: { $0.id == id }) else { return nil }
    let to = from + offset
    guard to >= 0, to < presets.count else { return nil }
    var reordered = presets
    let moved = reordered.remove(at: from)
    reordered.insert(moved, at: to)
    return reordered
}

/// Adds long-press drag-to-reorder to a quick-add preset chip, plus equivalent
/// "Move earlier/later" accessibility actions so the reordering the hint
/// advertises is actually reachable without a drag gesture. The drag payload is
/// the preset's UUID string; a drop from an unrelated source (foreign id) is a
/// no-op. On a successful reorder the bound list is updated and `persist` writes
/// it through to storage.
struct ReorderableChip<T: Identifiable>: ViewModifier where T.ID == UUID {
    let preset: T
    @Binding var presets: [T]
    let persist: ([T]) -> Void

    func body(content: Content) -> some View {
        content
            .draggable(preset.id.uuidString)
            .dropDestination(for: String.self) { dropped, _ in
                guard let dragged = dropped.first,
                      let reordered = reorderedByDrag(presets, draggedID: dragged, targetID: preset.id) else { return false }
                presets = reordered
                persist(reordered)
                return true
            }
            .accessibilityAction(named: "Move earlier") { move(by: -1) }
            .accessibilityAction(named: "Move later") { move(by: 1) }
    }

    private func move(by offset: Int) {
        guard let reordered = presetMoved(presets, id: preset.id, offset: offset) else { return }
        presets = reordered
        persist(reordered)
    }
}

// MARK: - Daily Bar Chart Card

/// The 30-day daily bar chart shared by the alcohol / nicotine / sauna trackers.
/// Each tracker supplies its own per-day totals as `DailyAmount`s; only the
/// title, bar color, unit labels, and accessibility description differ.
struct DailyBarChartCard: View {
    let title: String
    let data: [DailyAmount]
    /// Label for the bar's y-`value` (VoiceOver/inspector), e.g. "Grams", "mg", "Minutes".
    let barValueLabel: String
    /// `.chartYAxisLabel` shown beside the axis, e.g. "grams", "mg", "minutes".
    let yAxisLabel: String
    let color: Color
    let accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.textPrimary)

            Chart(data) { item in
                BarMark(
                    x: .value("Date", item.date),
                    y: .value(barValueLabel, item.amount)
                )
                .foregroundStyle(color.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                }
            }
            .chartYAxisLabel(yAxisLabel)
            .frame(height: Layout.chartFrameHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
        .padding()
        .cardStyle()
    }
}

// MARK: - Quick-Add Preset Row

/// A preset with a display name and a UUID identity — the shape `QuickAddPresetRow`
/// needs to render and reorder a tracker's quick-add chips.
protocol NamedPreset: Identifiable where ID == UUID {
    var name: String { get }
}

extension AlcoholPreset: NamedPreset {}
extension NicotinePreset: NamedPreset {}

/// The "Quick Add" card with a horizontal row of tappable preset chips, shared by
/// the alcohol and nicotine trackers (whose chips are plain name labels). Sauna's
/// quick-add uses a richer icon chip and keeps its own card. Each chip logs its
/// preset via `onAdd`, supports drag/accessibility reordering (persisted through
/// `persist`), and the header links to the preset manager via `onManage`.
struct QuickAddPresetRow<Preset: NamedPreset>: View {
    @Binding var presets: [Preset]
    /// VoiceOver hint for a chip, e.g. "Logs one Beer drink. Drag to reorder."
    let accessibilityHint: (Preset) -> String
    let onAdd: (Preset) -> Void
    let onManage: () -> Void
    let persist: ([Preset]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Add")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                managePresetsLink(action: onManage)
            }

            if presets.isEmpty {
                Text("No presets configured. Tap Manage Presets to add some.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { preset in
                            Button {
                                onAdd(preset)
                            } label: {
                                Text(preset.name)
                                    .font(.caption)
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.bgInput)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.cardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Quick add \(preset.name)")
                            .accessibilityHint(accessibilityHint(preset))
                            .modifier(ReorderableChip(preset: preset, presets: $presets, persist: persist))
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }
}

// MARK: - Substance History Row Chrome

/// The shared chrome for a substance history row: caption styling, zebra-striped
/// background, tap-to-edit, and an Edit/Delete context menu. The column content
/// (which differs per tracker) is supplied as the modified view; only the
/// accessibility label and the edit/delete actions vary.
struct SubstanceRowChrome: ViewModifier {
    let rowIndex: Int
    let accessibilityLabel: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.tableRowAlt)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Tap to edit")
            .accessibilityAddTraits(.isButton)
            .onTapGesture(perform: onEdit)
            .contextMenu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}
