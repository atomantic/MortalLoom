import SwiftUI

/// Full-screen "Doctor Visit" mode for the Genome screen. Walks the user
/// through their top priority findings one at a time so they can tick off what
/// they discussed and capture live notes during an appointment. iPad and large
/// canvases get a two-column layout (priorities list + `GenomeVisitNotesPane`);
/// iPhone gets the single focused pane advanced via "Save & Next".
///
/// The findings list is snapshotted on appear so saving a note — which reloads
/// and re-ranks priorities — doesn't reshuffle the visit mid-appointment. Notes
/// are kept as per-finding drafts here and only persisted when the user saves,
/// so jumping between findings in the list never loses typed-but-unsaved text.
struct GenomeVisitModeView: View {
    @Bindable var vm: GenomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sources: [PriorityFindingSource] = []
    @State private var selectedKey: String?
    @State private var providerLabel = ""
    @State private var visitDate = Date()
    @State private var drafts: [String: VisitDraft] = [:]
    @State private var savedKeys: Set<String> = []
    /// Note id persisted for each finding saved this visit, so returning to a
    /// finding and saving again updates that note instead of appending a copy.
    @State private var savedNoteIds: [String: UUID] = [:]
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    @State private var pdfExport: PDFExport?

    private struct VisitDraft { var note = ""; var followUp = "" }

    private var keys: [String] { sources.map(\.findingKey) }
    private var currentSource: PriorityFindingSource? {
        sources.first { $0.findingKey == selectedKey }
    }
    private var position: Int { GenomeVisitFlow.position(of: selectedKey, in: keys) }

    var body: some View {
        NavigationStack {
            content
                .readContainerWidth { containerWidth = $0 }
                .background(Color.bg)
                .navigationTitle("Doctor Visit")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { exportSummary() } label: {
                            Label("Export Summary", systemImage: "square.and.arrow.up")
                        }
                        .disabled(sources.isEmpty)
                        .accessibilityLabel("Export visit summary PDF")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .pdfExport($pdfExport)
        }
        .onAppear(perform: start)
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty {
            EmptyStateView(
                icon: "stethoscope",
                title: "Nothing to review yet",
                subtitle: "When findings surface in your priorities, start a visit to walk through them with your doctor."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                visitHeader
                Divider()
                columns
            }
        }
    }

    @ViewBuilder
    private var columns: some View {
        if genomeUsesSplitLayout(containerWidth: containerWidth) {
            twoColumn
        } else {
            paneOrEmpty
        }
    }

    private var twoColumn: some View {
        HStack(spacing: 0) {
            findingList
                .frame(width: 300)
            Divider()
            paneOrEmpty
        }
    }

    private var visitHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Provider (optional)", text: $providerLabel)
                    .textFieldStyle(.roundedBorder)
                DatePicker("", selection: $visitDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            HStack(spacing: 12) {
                Button { goPrev() } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(position <= 1)
                .accessibilityLabel("Previous finding")

                Spacer()
                Text("Finding \(position) of \(sources.count) · \(savedKeys.count) noted")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                Spacer()

                Button { goNext() } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(position >= sources.count)
                .accessibilityLabel("Next finding")
            }
            ProgressView(value: Double(savedKeys.count), total: Double(max(sources.count, 1)))
                .tint(.accentColor)
        }
        .padding()
        .background(Color.bgCard)
    }

    private var findingList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sources, id: \.findingKey) { source in
                    listRow(source)
                    Divider()
                }
            }
        }
        .background(Color.bg)
    }

    private func listRow(_ source: PriorityFindingSource) -> some View {
        let selected = source.findingKey == selectedKey
        return Button { withAnimation { selectedKey = source.findingKey } } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(severityColor(for: source))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(source.statusLabel)
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
                Spacer()
                if savedKeys.contains(source.findingKey) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.success)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var paneOrEmpty: some View {
        if let source = currentSource {
            GenomeVisitNotesPane(
                finding: source,
                actions: vm.actionsForFinding(source),
                actionStates: vm.actionStates,
                priorVisitNotes: priorNotes(for: source),
                position: position,
                total: sources.count,
                isLast: GenomeVisitFlow.isLast(selectedKey, in: keys),
                noteText: draftBinding(source.findingKey, \.note),
                followUp: draftBinding(source.findingKey, \.followUp),
                onToggleAction: { toggle($0, for: source) },
                onSaveAndNext: { saveAndAdvance() },
                onSkip: { advance() }
            )
            // Reset the pane's transient @State (copy toast) per finding so it
            // doesn't carry over when the user advances.
            .id(source.findingKey)
        } else {
            EmptyStateView(
                icon: "checkmark.seal",
                title: "Visit complete",
                subtitle: "Tap Done to return to your genome findings."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - State

    private func start() {
        guard sources.isEmpty else { return }
        sources = vm.topPriorities.map(\.source)
        selectedKey = sources.first?.findingKey
    }

    /// Build the post-visit summary PDF — the findings walked through, the notes
    /// captured this visit (with follow-ups), and drug-response variants — and
    /// hand it to the export UI (share sheet on iOS, file exporter on macOS).
    private func exportSummary() {
        let savedIds = Set(savedNoteIds.values)
        let notes = vm.visitNotes.filter { savedIds.contains($0.id) }
        let content = GenomeReport.postvisit(
            findings: sources,
            clinvarHits: vm.clinvarHits,
            notes: notes,
            date: visitDate,
            provider: providerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : providerLabel
        )
        pdfExport = PDFExport(
            data: GenomeReport.pdfData(for: content),
            filename: GenomeReport.filename(prefix: "VisitSummary", date: visitDate)
        )
    }

    private func priorNotes(for source: PriorityFindingSource) -> [VisitNote] {
        vm.visitNotes
            .filter { $0.findingKey == source.findingKey }
            .sorted { $0.date > $1.date }
    }

    /// One binding factory for both draft fields — `\.note` and `\.followUp`
    /// differ only by key path, so they share this rather than duplicating the
    /// get/set boilerplate.
    private func draftBinding(_ key: String, _ field: WritableKeyPath<VisitDraft, String>) -> Binding<String> {
        Binding(
            get: { drafts[key]?[keyPath: field] ?? "" },
            set: { drafts[key, default: VisitDraft()][keyPath: field] = $0 }
        )
    }

    private func toggle(_ action: GenomeAction, for source: PriorityFindingSource) {
        let key = GenomeActionState.key(rsid: source.findingKey, actionId: action.id)
        let status = vm.actionStates[key]?.status
        // `.done` is a stronger, deliberately-set completion state — leave it
        // intact (the checkbox shows it as checked). The visit checkbox only
        // flips the discussed/pending pair captured during the appointment.
        guard status != .done else { return }
        vm.markActionStatus(finding: source, action: action, status: status == .discussed ? .pending : .discussed)
    }

    private func saveAndAdvance() {
        saveCurrent()
        advance()
    }

    private func saveCurrent() {
        guard let source = currentSource else { return }
        let key = source.findingKey
        let draft = drafts[key] ?? VisitDraft()
        let existingId = savedNoteIds[key]
        guard let note = GenomeVisitFlow.makeNote(
            id: existingId ?? UUID(),
            date: visitDate,
            providerLabel: providerLabel,
            findingKey: key,
            body: draft.note,
            followUp: draft.followUp
        ) else { return }
        if existingId == nil {
            savedNoteIds[key] = note.id
            // Don't bulk auto-discuss pending actions — the checklist toggles
            // are authoritative in Visit Mode, so an unchecked action stays
            // pending even when a note is saved.
            Task { await vm.addVisitNote(note, autoDiscussPending: false) }
        } else {
            // Already saved this visit — update the same note rather than
            // appending a duplicate.
            Task { await vm.updateVisitNote(note) }
        }
        savedKeys.insert(key)
    }

    private func advance() {
        if let next = GenomeVisitFlow.nextKey(after: selectedKey, in: keys) {
            withAnimation { selectedKey = next }
        } else {
            dismiss()
        }
    }

    private func goPrev() {
        guard let key = selectedKey,
              let idx = keys.firstIndex(of: key), idx > 0 else { return }
        withAnimation { selectedKey = keys[idx - 1] }
    }

    private func goNext() {
        if let next = GenomeVisitFlow.nextKey(after: selectedKey, in: keys) {
            withAnimation { selectedKey = next }
        }
    }
}
