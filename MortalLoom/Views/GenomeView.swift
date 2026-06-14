import SwiftUI
import UniformTypeIdentifiers

/// Host for the three Genome tabs (`EpigeneticAgeView`, `GenomeScanView`,
/// `ClinVarView`). Owns the tab control (segmented + modal detail on iPhone, a
/// three-column `GenomeSplitView` on iPad regular width — #50), the file
/// importer + sheet presentations, and the `.openGenomeFinding`/`.dataDidSync`
/// wiring; all data loading, scan orchestration, and action state live in
/// `GenomeViewModel` (extracted in issue #24).
struct GenomeView: View {
    @State private var vm = GenomeViewModel()
    @State private var activeTab: GenomeTab = .bioAge
    @State private var showingAddTest = false
    @State private var showingFileImporter = false
    @State private var containerWidth: CGFloat = Layout.defaultContainerWidth
    private var isWide: Bool { containerWidth >= Layout.wideThreshold }

    var body: some View {
        layoutContent
            .readContainerWidth { containerWidth = $0 }
            .background(Color.bg)
            .pdfExport($vm.pdfExport)
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
        .modifier(GenomeVisitModePresenter(isPresented: $vm.showingVisitMode, vm: vm))
        .task { await vm.load() }
        .onDisappear { vm.cancelScans() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await vm.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGenomeFinding)) { notif in
            guard let key = notif.object as? String else { return }
            // Switch to the Genome tab so the sheet/pane has a host.
            activeTab = .genome
            vm.requestFinding(forKey: key)
        }
    }

    // MARK: - Layout

    /// On iPad regular width the screen becomes a three-column
    /// `NavigationSplitView` (`GenomeSplitView`) with the finding detail as the
    /// right pane (#50). iPhone — and iPad Slide Over / narrow widths — keep the
    /// segmented single column with the detail as a modal sheet; macOS keeps the
    /// single column + `.inspector` (it already has a side pane and its own
    /// `NavigationSplitView` host, so it doesn't nest a second one here).
    @ViewBuilder
    private var layoutContent: some View {
        #if os(iOS)
        if genomeUsesSplitLayout(containerWidth: containerWidth) {
            GenomeSplitView(
                vm: vm,
                activeTab: $activeTab,
                showingAddTest: $showingAddTest,
                showingFileImporter: $showingFileImporter
            )
        } else {
            singleColumn.modifier(detailPresenter)
        }
        #else
        singleColumn.modifier(detailPresenter)
        #endif
    }

    private var detailPresenter: GenomeDetailPresenter<GenomeDetailSheet> {
        GenomeDetailPresenter(
            selectedFinding: $vm.selectedFinding,
            buildSheet: { finding in genomeDetailSheet(vm: vm, finding: finding, embedded: false) }
        )
    }

    private var singleColumn: some View {
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
                    genomeTabBody(
                        vm: vm,
                        activeTab: activeTab,
                        showingAddTest: $showingAddTest,
                        showingFileImporter: $showingFileImporter
                    )
                }
                .padding()
                // Cap the single-column content to a readable width and center
                // it on wide canvases (macOS windows, wide iPhone landscape) so
                // charts/lists don't stretch edge-to-edge. iPad regular width
                // uses GenomeSplitView instead of this single column.
                .frame(maxWidth: isWide ? Layout.wideThreshold : .infinity)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Visit Mode presenter (full-screen cover on iOS, sheet on macOS)

/// Presents `GenomeVisitModeView` adaptively: a `.fullScreenCover` on iOS so the
/// focused appointment flow takes over the screen, and a sized `.sheet` on macOS
/// (which has no full-screen cover). Raised by the "Start Doctor Visit" button in
/// `GenomePrioritiesCard` via `vm.showingVisitMode`.
private struct GenomeVisitModePresenter: ViewModifier {
    @Binding var isPresented: Bool
    let vm: GenomeViewModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented) {
            GenomeVisitModeView(vm: vm)
        }
        #else
        content.sheet(isPresented: $isPresented) {
            GenomeVisitModeView(vm: vm)
                .frame(minWidth: 840, minHeight: 600)
        }
        #endif
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
