import SwiftUI

/// The focused per-finding capture surface for Genome Visit Mode. On iPad it's
/// the right column of `GenomeVisitModeView`'s two-column layout (priorities
/// list on the left); on iPhone it's the whole screen, advanced via the bottom
/// "Save & Next" button. Shows the finding's doctor talking point, a checklist
/// of curated actions the user ticks off as they're discussed, and a live notes
/// field whose text is persisted as a `VisitNote` when the user saves.
struct GenomeVisitNotesPane: View {
    let finding: PriorityFindingSource
    let actions: [GenomeAction]
    let actionStates: [String: GenomeActionState]
    /// Notes previously saved against this finding (read-only context).
    let priorVisitNotes: [VisitNote]
    let position: Int
    let total: Int
    let isLast: Bool
    @Binding var noteText: String
    @Binding var followUp: String
    /// Toggle an action between `discussed` and `pending` as it's checked off.
    let onToggleAction: (GenomeAction) -> Void
    /// Persist the current note (if any) and advance to the next finding.
    let onSaveAndNext: () -> Void
    /// Advance without saving the current note.
    let onSkip: () -> Void

    @State private var showCopyToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let talkingPoint {
                    talkingPointCard(talkingPoint)
                }
                checklistCard
                notesCard
                if !priorVisitNotes.isEmpty {
                    priorNotesCard
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bg)
        .overlay(alignment: .top) {
            if showCopyToast {
                Text("Copied to clipboard")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finding \(position) of \(total)")
                .font(.caption2)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundColor(.textMuted)
            HStack(spacing: 10) {
                Image(systemName: headerIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let genotype = displayGenotype {
                        Text(genotype)
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(statusColor)
                    }
                }
                Spacer()
                statusPill
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.06))
        .cardStyle()
    }

    private func talkingPointCard(_ talkingPoint: String) -> some View {
        sectionCard(title: "Doctor talking point") {
            Text(talkingPoint)
                .font(.subheadline)
                .italic()
                .foregroundColor(.textPrimary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgInput)
                .cornerRadius(8)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { copyToClipboard(talkingPoint) }) {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
    }

    private var checklistCard: some View {
        sectionCard(title: "Discussed checklist") {
            if actions.isEmpty {
                Text("No curated actions for this finding yet — capture anything your provider says in the notes below.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(actions, id: \.id) { action in
                        checklistRow(action)
                    }
                }
            }
        }
    }

    private func checklistRow(_ action: GenomeAction) -> some View {
        let checked = isChecked(action)
        return Button(action: { onToggleAction(action) }) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundColor(checked ? .success : .textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .strikethrough(checked, color: .textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(action.kind.label, systemImage: action.kind.icon)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgInput)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(action.title), \(checked ? "discussed" : "not discussed")")
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private var notesCard: some View {
        sectionCard(title: "Visit notes") {
            TextEditor(text: $noteText)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.bgInput)
                .cornerRadius(8)
                .overlay(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("What did your provider say?")
                            .font(.subheadline)
                            .foregroundColor(.textMuted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            TextField("Follow-up (optional) — e.g. recheck in 3 months", text: $followUp)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var priorNotesCard: some View {
        sectionCard(title: "Earlier notes (\(priorVisitNotes.count))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(priorVisitNotes, id: \.id) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(DateFormatting.displayDate(note.date))
                                .font(.caption2)
                                .foregroundColor(.textMuted)
                            if let provider = note.providerLabel, !provider.isEmpty {
                                Text("·").foregroundColor(.textMuted)
                                Text(provider)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        Text(note.body)
                            .font(.caption)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgInput)
                    .cornerRadius(6)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: onSkip) {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: onSaveAndNext) {
                Label(isLast ? "Save & Finish" : "Save & Next",
                      systemImage: isLast ? "checkmark" : "arrow.right")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundColor(.textMuted)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func isChecked(_ action: GenomeAction) -> Bool {
        let key = GenomeActionState.key(rsid: finding.findingKey, actionId: action.id)
        let status = actionStates[key]?.status
        return status == .discussed || status == .done
    }

    private var talkingPoint: String? {
        actions.compactMap(\.doctorTalkingPoint).first
    }

    private var statusColor: Color { severityColor(for: finding) }

    private var statusPill: some View {
        Text(finding.statusLabel)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .cornerRadius(6)
    }

    private var headerIcon: String {
        switch finding {
        case .marker(let r): r.marker.category.icon
        case .clinvar: "building.columns.fill"
        case .apoe: "brain.head.profile"
        }
    }

    private var displayGenotype: String? {
        switch finding {
        case .marker(let r): r.genotype
        case .clinvar(let h): h.genotype
        case .apoe(let a): a.haplotype
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation { showCopyToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { withAnimation { showCopyToast = false } }
        }
    }
}
