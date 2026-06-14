import SwiftUI

/// Lightweight inline form for adding a single doctor visit note from the
/// genome detail sheet. The bigger live-capture flow that walks every priority
/// finding lives in `GenomeVisitModeView` (Visit Mode).
struct VisitNoteSheet: View {
    let finding: PriorityFindingSource
    let onSave: (VisitNote) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var providerLabel: String = ""
    @State private var noteBody: String = ""
    @State private var followUp: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    TextField("Provider (e.g. Dr. Patel — PCP)", text: $providerLabel)
                }

                Section("Notes from this visit") {
                    TextField("What did your provider say?", text: $noteBody, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section("Follow-up (optional)") {
                    TextField("e.g. Order homocysteine in 2 weeks", text: $followUp)
                }

                Section {
                    Text("Saving auto-marks any pending actions on this finding as 'Discussed' so they drop out of your priorities.")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
            }
            .macGroupedFormStyle()
            .navigationTitle("Add Visit Note")
            .inlineNavigationTitle()
            .macSheetFrame()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(noteBody.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let note = VisitNote(
            date: DateFormatting.dateString(date),
            providerLabel: providerLabel.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : providerLabel.trimmingCharacters(in: .whitespaces),
            findingKey: finding.findingKey,
            body: noteBody.trimmingCharacters(in: .whitespaces),
            followUp: followUp.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : followUp.trimmingCharacters(in: .whitespaces)
        )
        onSave(note)
        dismiss()
    }
}
