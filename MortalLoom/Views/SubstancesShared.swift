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
