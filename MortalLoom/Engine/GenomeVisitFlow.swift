import Foundation

/// Pure navigation + note-construction helpers for Genome Visit Mode
/// (`GenomeVisitModeView`). Kept framework-free and side-effect-free so the
/// "Save & Next" sequencing and the draft→`VisitNote` trimming rules are unit
/// testable in isolation — the view just renders what these return.
enum GenomeVisitFlow {

    /// The finding key that follows `current` in `order`. Returns `nil` when
    /// `current` is the last entry, is absent from `order`, or `order` is empty
    /// — the view reads `nil` as "visit complete" and dismisses.
    static func nextKey(after current: String?, in order: [String]) -> String? {
        guard let current, let idx = order.firstIndex(of: current) else { return nil }
        let next = idx + 1
        return next < order.count ? order[next] : nil
    }

    /// Whether `key` is the final finding in `order`, so the primary button can
    /// read "Save & Finish" instead of "Save & Next".
    static func isLast(_ key: String?, in order: [String]) -> Bool {
        guard let key, let idx = order.firstIndex(of: key) else { return false }
        return idx == order.count - 1
    }

    /// 1-based position of `key` within `order`, or 0 if absent. Drives the
    /// "Finding X of N" progress label.
    static func position(of key: String?, in order: [String]) -> Int {
        guard let key, let idx = order.firstIndex(of: key) else { return 0 }
        return idx + 1
    }

    /// Build a `VisitNote` from raw Visit Mode inputs, trimming whitespace and
    /// collapsing empty optional fields to `nil`. Returns `nil` when the note
    /// body is blank after trimming — there's nothing worth persisting, so
    /// "Save & Next" just advances without writing an empty note.
    static func makeNote(
        id: UUID = UUID(),
        date: Date,
        providerLabel: String,
        findingKey: String,
        body: String,
        followUp: String
    ) -> VisitNote? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }
        let provider = providerLabel.trimmingCharacters(in: .whitespaces)
        let trimmedFollowUp = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        return VisitNote(
            id: id,
            date: DateFormatting.dateString(date),
            providerLabel: provider.isEmpty ? nil : provider,
            findingKey: findingKey,
            body: trimmedBody,
            followUp: trimmedFollowUp.isEmpty ? nil : trimmedFollowUp
        )
    }
}
