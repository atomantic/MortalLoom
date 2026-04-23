import SwiftUI

// MARK: - Genome Finding (input wrapper)

/// Wraps the three things the detail sheet can describe: a curated marker
/// result, a ClinVar hit, or an APOE haplotype. `findingKey` is the storage
/// key used in `AppData.genomeActionStates` (rsid for marker/APOE,
/// "rsid:condition" for ClinVar).
enum GenomeFinding: Sendable, Hashable, Identifiable {
    case marker(MarkerResult)
    case clinvar(ClinVarHit)
    case apoe(APOEResult)

    var id: String { findingKey }

    var findingKey: String {
        switch self {
        case .marker(let r): r.marker.rsid
        case .clinvar(let h):
            if let cond = h.entry.conditions.first, !cond.isEmpty {
                "\(h.rsid):\(cond.lowercased())"
            } else {
                h.rsid
            }
        case .apoe: "apoe"
        }
    }

    var lookupRsid: String {
        switch self {
        case .marker(let r): r.marker.rsid
        case .clinvar(let h): h.rsid
        case .apoe: "apoe"
        }
    }

    static func == (lhs: GenomeFinding, rhs: GenomeFinding) -> Bool {
        lhs.findingKey == rhs.findingKey
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(findingKey)
    }
}

// MARK: - Detail Sheet

/// Single detail surface used everywhere a genome finding is opened. Presented
/// as a `.sheet(.large)` on iPhone and as the right pane of `GenomeSplitView`
/// on iPad. **No truncation in this view, ever.**
struct GenomeDetailSheet: View {
    let finding: GenomeFinding
    let actionStates: [String: GenomeActionState]
    let visitNotes: [VisitNote]
    let linkedHabits: [Habit]
    let linkedGoals: [Goal]
    /// Whether to render an embedded layout (no toolbar/close, used inside
    /// `GenomeSplitView`'s right pane on iPad). Phone presentation passes false.
    let embedded: Bool
    /// Routed to the parent which presents the appropriate sheet/page.
    let onBridge: (GenomeAction, GenomeActionBridge) -> Void
    /// Mark "discussed" without creating a visit note (acknowledgement).
    let onMarkDiscussed: (GenomeAction) -> Void
    let onMarkDone: (GenomeAction) -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void
    let onAddVisitNote: (GenomeAction?) -> Void
    let onCloseSheet: (() -> Void)?

    @State private var showCopyToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                whatThisMeansSection
                actionPlanSection
                if let talkingPoint = effectiveTalkingPoint {
                    doctorTalkingPointSection(talkingPoint)
                }
                if !relevantVisitNotes.isEmpty {
                    visitNotesSection
                }
                if !linkedHabits.isEmpty || !linkedGoals.isEmpty {
                    linkedItemsSection
                }
                evidenceSection
                snoozeDismissSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
        .toolbar {
            if !embedded, let onCloseSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onCloseSheet() }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: headerIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundColor(.textMuted)
                        .monospacedDigit()
                }
                Spacer()
                statusPill
            }

            HStack(spacing: 8) {
                if let genotype = displayGenotype {
                    HStack(spacing: 4) {
                        Text("Your genotype")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                        Text(genotype)
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statusColor.opacity(0.12))
                            .foregroundColor(statusColor)
                            .cornerRadius(6)
                    }
                }
                if let stars = clinvarStars {
                    HStack(spacing: 1) {
                        ForEach(0..<4, id: \.self) { i in
                            Image(systemName: i < stars ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(i < stars ? .orange : .textMuted)
                        }
                    }
                }
            }
        }
        .padding()
        .background(statusColor.opacity(0.06))
        .cardStyle()
    }

    private var whatThisMeansSection: some View {
        sectionCard(title: "What this means") {
            Text(fullDescription)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !implicationText.isEmpty {
                Text(implicationText)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .padding(10)
                    .background(statusColor.opacity(0.07))
                    .cornerRadius(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionPlanSection: some View {
        sectionCard(title: "Action plan") {
            if relevantActions.isEmpty {
                Text("No specific actions yet for this finding. As we expand the curated library, suggestions will appear here.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(relevantActions, id: \.id) { action in
                        actionRow(action)
                    }
                }
            }
        }
    }

    private func actionRow(_ action: GenomeAction) -> some View {
        let state = actionStates[GenomeActionState.key(rsid: finding.findingKey, actionId: action.id)]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(urgencyColor(action.urgency))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 6) {
                        Text(action.urgency.label).font(.caption2).foregroundColor(urgencyColor(action.urgency))
                        Text("·").foregroundColor(.textMuted)
                        Label(action.kind.label, systemImage: action.kind.icon)
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
                if let state {
                    actionStatusBadge(state.status)
                }
            }
            Text(action.detail)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .padding(.leading, 16)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let bridge = action.bridge {
                    Button(action: { onBridge(action, bridge) }) {
                        Text(primaryCTALabel(for: bridge))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                if state?.status != .discussed && state?.status != .done {
                    Button(action: { onMarkDiscussed(action) }) {
                        Text("Mark discussed")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                if action.kind == .supplement || action.kind == .lifestyle {
                    if state?.status != .done {
                        Button(action: { onMarkDone(action) }) {
                            Text("Mark done")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.bgInput)
        .cornerRadius(8)
    }

    private func doctorTalkingPointSection(_ talkingPoint: String) -> some View {
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
            HStack(spacing: 8) {
                Button(action: { copyToClipboard(talkingPoint) }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                Button(action: { onAddVisitNote(nil) }) {
                    Label("Add to visit notes", systemImage: "square.and.pencil")
                        .font(.caption)
                }
                Spacer()
            }
        }
    }

    private var visitNotesSection: some View {
        sectionCard(title: "Visit notes (\(relevantVisitNotes.count))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(relevantVisitNotes, id: \.id) { note in
                    visitNoteRow(note)
                }
            }
        }
    }

    private func visitNoteRow(_ note: VisitNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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
            if let followUp = note.followUp, !followUp.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.right.circle")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text("Follow-up: \(followUp)")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgInput)
        .cornerRadius(6)
    }

    private var linkedItemsSection: some View {
        sectionCard(title: "Linked items") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(linkedHabits, id: \.id) { habit in
                    HStack(spacing: 6) {
                        Image(systemName: habit.icon)
                            .font(.caption)
                            .foregroundColor(habit.color)
                        Text("Habit: \(habit.name)")
                            .font(.caption)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(habit.completions.count) total")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                    }
                }
                ForEach(linkedGoals, id: \.id) { goal in
                    HStack(spacing: 6) {
                        Image(systemName: goal.category?.icon ?? "target")
                            .font(.caption)
                            .foregroundColor(goal.category?.swiftUIColor ?? .accentColor)
                        Text("Goal: \(goal.title)")
                            .font(.caption)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(Int(goal.progressPercent))%")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                    }
                }
            }
        }
    }

    private var evidenceSection: some View {
        sectionCard(title: "Evidence") {
            VStack(alignment: .leading, spacing: 8) {
                if case .clinvar(let hit) = finding {
                    HStack(spacing: 4) {
                        Text("ClinVar:")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                        Text("\(hit.entry.reviewStars)★ · \(hit.entry.submissions) submission\(hit.entry.submissions == 1 ? "" : "s") · \(hit.entry.severity.replacingOccurrences(of: "_", with: " ").capitalized)")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    if !hit.entry.conditions.isEmpty {
                        Text("Conditions:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.textSecondary)
                        Text(hit.entry.conditions.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !allCitationIds.isEmpty {
                    CitationBadge(
                        ids: allCitationIds,
                        claim: "Sources backing the description and curated actions for this finding."
                    )
                }
            }
        }
    }

    private var snoozeDismissSection: some View {
        HStack(spacing: 12) {
            Button(action: onSnooze) {
                Label("Snooze 6 months", systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            Spacer()
            Button(action: onDismiss) {
                Label("Not relevant — dismiss", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
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

    private var headerTitle: String {
        switch finding {
        case .marker(let r): r.marker.gene + (r.marker.name.isEmpty ? "" : " — \(r.marker.name)")
        case .clinvar(let h): h.entry.gene.isEmpty ? h.rsid : h.entry.gene
        case .apoe(let a): "APOE \(a.haplotype)"
        }
    }

    private var headerSubtitle: String {
        switch finding {
        case .marker(let r): r.marker.rsid
        case .clinvar(let h): h.rsid
        case .apoe: "rs429358 + rs7412"
        }
    }

    private var headerIcon: String {
        switch finding {
        case .marker(let r): r.marker.category.icon
        case .clinvar: "building.columns.fill"
        case .apoe: "brain.head.profile"
        }
    }

    private var statusPill: some View {
        Text(statusLabel)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .cornerRadius(6)
    }

    private var statusLabel: String {
        switch finding {
        case .marker(let r):
            switch r.status {
            case .majorConcern: "Major Concern"
            case .concern: "Concern"
            case .beneficial: "Beneficial"
            case .typical: "Typical"
            case .notFound: "Not Found"
            }
        case .clinvar(let h):
            switch h.entry.severity {
            case "pathogenic": "Pathogenic"
            case "risk_factor": "Risk Factor"
            case "drug_response": "Drug Response"
            case "protective": "Protective"
            default: h.entry.severity.capitalized
            }
        case .apoe(let a):
            switch a.status {
            case .majorConcern: "Major Concern"
            case .concern: "Concern"
            case .beneficial: "Beneficial"
            default: "Typical"
            }
        }
    }

    private var statusColor: Color {
        switch finding {
        case .marker(let r):
            switch r.status {
            case .majorConcern: .red
            case .concern: .orange
            case .beneficial: .green
            case .typical: .secondary
            case .notFound: .gray
            }
        case .clinvar(let h):
            switch h.entry.severity {
            case "pathogenic": .red
            case "risk_factor", "drug_response": .orange
            case "protective": .green
            default: .secondary
            }
        case .apoe(let a):
            switch a.status {
            case .majorConcern: .red
            case .concern: .orange
            case .beneficial: .green
            default: .secondary
            }
        }
    }

    private var displayGenotype: String? {
        switch finding {
        case .marker(let r): r.genotype
        case .clinvar(let h): h.genotype
        case .apoe(let a): a.haplotype
        }
    }

    private var clinvarStars: Int? {
        if case .clinvar(let h) = finding { return h.entry.reviewStars }
        return nil
    }

    private var fullDescription: String {
        switch finding {
        case .marker(let r): r.marker.description
        case .clinvar(let h):
            "Variant \(h.rsid) in \(h.entry.gene.isEmpty ? "this gene" : h.entry.gene) is classified as \(h.entry.severity.replacingOccurrences(of: "_", with: " ")) by ClinVar with \(h.entry.reviewStars)-star review confidence (\(h.entry.submissions) clinical submission\(h.entry.submissions == 1 ? "" : "s"))."
        case .apoe(let a): a.implication
        }
    }

    private var implicationText: String {
        switch finding {
        case .marker(let r): r.implication
        case .clinvar(let h):
            h.entry.conditions.isEmpty ? "" : "Associated conditions: \(h.entry.conditions.joined(separator: ", "))"
        case .apoe: ""
        }
    }

    private var relevantActions: [GenomeAction] {
        switch finding {
        case .marker(let r):
            return GenomePriorityEngine.matchingActions(
                forRsid: r.marker.rsid,
                genotype: r.genotype,
                status: r.status,
                in: GenomeActionLibrary.all
            )
        case .apoe(let a):
            return GenomeActionLibrary.all.filter { action in
                action.conditions.contains { $0.rsid == "apoe"
                    && ($0.genotypes?.contains(a.haplotype) ?? true) }
            }
        case .clinvar(let h):
            let pseudo = "clinvar:\(h.entry.severity)"
            return GenomeActionLibrary.all.filter { action in
                action.conditions.contains { $0.rsid == h.rsid || $0.rsid == pseudo }
            }
        }
    }

    private var relevantVisitNotes: [VisitNote] {
        visitNotes.filter { $0.findingKey == finding.findingKey }
            .sorted { $0.date > $1.date }
    }

    private var effectiveTalkingPoint: String? {
        // Prefer a marker/APOE-level talking point from any matching action.
        relevantActions.compactMap(\.doctorTalkingPoint).first
    }

    private var allCitationIds: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for action in relevantActions {
            for id in action.citationIds where !seen.contains(id) {
                seen.insert(id)
                out.append(id)
            }
        }
        if case .clinvar = finding {
            if !seen.contains(CitationLibrary.clinvar.id) {
                seen.insert(CitationLibrary.clinvar.id)
                out.append(CitationLibrary.clinvar.id)
            }
        }
        return out
    }

    private func urgencyColor(_ urgency: GenomeActionUrgency) -> Color {
        switch urgency {
        case .routine: .gray
        case .soon: .orange
        case .prompt: .red
        }
    }

    private func actionStatusBadge(_ status: GenomeActionStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .pending: ("Pending", .secondary)
            case .inProgress: ("In progress", .accentColor)
            case .discussed: ("Discussed", .green)
            case .done: ("Done", .green)
            case .snoozed: ("Snoozed", .gray)
            case .dismissed: ("Dismissed", .gray)
            }
        }()
        return Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }

    private func primaryCTALabel(for bridge: GenomeActionBridge) -> String {
        switch bridge {
        case .habitTemplate: "Add as habit"
        case .goalTemplate: "Set as goal"
        case .bloodMarkerKey: "Open in Blood"
        case .lifestyleField: "Open in Lifestyle"
        case .external: "Open source"
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
