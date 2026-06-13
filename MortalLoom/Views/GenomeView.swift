import SwiftUI
import UniformTypeIdentifiers

/// Host for the three Genome tabs (`EpigeneticAgeView`, `GenomeScanView`,
/// `ClinVarView`). Owns the segmented tab control, the file importer + sheet
/// presentations, and the `.openGenomeFinding`/`.dataDidSync` wiring; all data
/// loading, scan orchestration, and action state live in `GenomeViewModel`
/// (extracted in issue #24).
struct GenomeView: View {
    @State private var vm = GenomeViewModel()
    @State private var activeTab: GenomeTab = .bioAge
    @State private var showingAddTest = false
    @State private var showingFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $activeTab) {
                ForEach(GenomeTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.bgCard)

            ScrollView {
                VStack(spacing: 16) {
                    switch activeTab {
                    case .bioAge:
                        EpigeneticAgeView(vm: vm, showingAddTest: $showingAddTest)
                    case .genome:
                        GenomeScanView(vm: vm, showingFileImporter: $showingFileImporter)
                    case .clinvar:
                        ClinVarView(vm: vm)
                    }
                }
                .padding()
            }
        }
        .background(Color.bg)
        .proGated()
        .sheet(isPresented: $showingAddTest) {
            EpigeneticTestFormView(onSave: { test in
                Task { await vm.addEpigeneticTest(test) }
            })
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText, .text, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            vm.handleFileImport(result)
        }
        .modifier(GenomeDetailPresenter(
            selectedFinding: $vm.selectedFinding,
            buildSheet: { finding in
                GenomeDetailSheet(
                    finding: finding,
                    actionStates: vm.actionStates,
                    visitNotes: vm.visitNotes,
                    linkedHabits: vm.linkedHabits(for: finding),
                    linkedGoals: vm.linkedGoals(for: finding),
                    embedded: false,
                    onBridge: { action, bridge in vm.handleBridge(finding: finding, action: action, bridge: bridge) },
                    onMarkDiscussed: { action in vm.markActionStatus(finding: finding, action: action, status: .discussed) },
                    onMarkDone: { action in vm.markActionStatus(finding: finding, action: action, status: .done) },
                    onSnooze: { vm.snoozeAllActions(for: finding) },
                    onDismiss: { vm.dismissAllActions(for: finding) },
                    onSaveVisitNote: { note in
                        Task { await vm.addVisitNote(note) }
                    },
                    onCloseSheet: { vm.selectedFinding = nil }
                )
            }
        ))
        .sheet(item: $vm.pendingHabitTemplate) { template in
            HabitEditSheet(
                habit: vm.prefilledHabit(from: template),
                goals: vm.allGoals,
                prefillEvidence: vm.pendingHabitEvidence
            ) { newHabit in
                Task { await vm.completeHabitBridge(newHabit) }
            }
        }
        .sheet(item: $vm.pendingGoalTemplate) { template in
            GoalEditSheet(
                goal: vm.prefilledGoal(from: template),
                allGoals: vm.allGoals,
                allHabits: vm.allHabits,
                prefillEvidence: vm.pendingGoalEvidence,
                onSave: { newGoal in
                    Task { await vm.completeGoalBridge(newGoal) }
                }
            )
        }
        .task { await vm.load() }
        .onDisappear { vm.cancelScans() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await vm.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGenomeFinding)) { notif in
            guard let key = notif.object as? String else { return }
            // Switch to the Genome tab so the sheet has a host.
            activeTab = .genome
            vm.requestFinding(forKey: key)
        }
    }
}

// MARK: - Detail presenter (sheet on iOS, inspector on macOS)

/// Presents `GenomeDetailSheet` adaptively. On iOS the detail is a `.sheet`;
/// on macOS it lives in an `.inspector` so the user can see it alongside the
/// genome content rather than as a blocking modal.
private struct GenomeDetailPresenter<Sheet: View>: ViewModifier {
    @Binding var selectedFinding: PriorityFindingSource?
    let buildSheet: (PriorityFindingSource) -> Sheet

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .inspector(isPresented: Binding(
                get: { selectedFinding != nil },
                set: { if !$0 { selectedFinding = nil } }
            )) {
                if let finding = selectedFinding {
                    buildSheet(finding)
                        .inspectorColumnWidth(min: 480, ideal: 560, max: 800)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Close") { selectedFinding = nil }
                            }
                        }
                } else {
                    EmptyView()
                }
            }
        #else
        content.sheet(item: $selectedFinding) { finding in
            NavigationStack {
                buildSheet(finding)
            }
            .presentationDetents([.large])
        }
        #endif
    }
}
