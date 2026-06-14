import SwiftUI

#if os(iOS)
/// iPad regular-width Genome layout: a three-column `NavigationSplitView`
/// (section sidebar / content / finding detail). It replaces the segmented
/// picker + modal `.sheet` detail that `GenomeView` uses on iPhone so a tapped
/// marker/ClinVar/priority opens in the right pane *alongside* the content
/// instead of covering it. `GenomeView` swaps to this only when the container
/// is wide (`GenomeLayout.usesSplit`); narrow widths keep the single column.
///
/// State (`vm`, `activeTab`, the importer/add-test flags) is owned by
/// `GenomeView` and threaded in by binding, so the modal sheets it presents
/// (file import, add-test, habit/goal bridges) and the `.openGenomeFinding`
/// tab-switch keep working unchanged regardless of which layout is active.
struct GenomeSplitView: View {
    @Bindable var vm: GenomeViewModel
    @Binding var activeTab: GenomeTab
    @Binding var showingAddTest: Bool
    @Binding var showingFileImporter: Bool

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            content
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar (section list)

    private var sidebar: some View {
        List(GenomeTab.allCases, id: \.self, selection: sidebarSelection) { tab in
            Label(tab.rawValue, systemImage: tab.icon).tag(tab)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Genome")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    /// `List(selection:)` wants an optional binding; map it onto the
    /// non-optional `activeTab` (ignoring a programmatic clear so the content
    /// column never blanks out).
    private var sidebarSelection: Binding<GenomeTab?> {
        Binding(
            get: { activeTab },
            set: { if let tab = $0 { activeTab = tab } }
        )
    }

    // MARK: - Content (selected tab)

    private var content: some View {
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
            .frame(maxWidth: .infinity)
        }
        .background(Color.bg)
        .navigationTitle(activeTab.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .navigationSplitViewColumnWidth(min: 320, ideal: 420)
    }

    // MARK: - Detail (selected finding)

    @ViewBuilder
    private var detail: some View {
        if let finding = vm.selectedFinding {
            // `embedded: true` drops the sheet's toolbar Close — in the split
            // layout the pane is dismissed by selecting another finding, not by
            // a modal close button.
            genomeDetailSheet(vm: vm, finding: finding, embedded: true)
        } else {
            // Reuse the shared empty-state component, centered to fill the pane.
            EmptyStateView(
                icon: "atom",
                title: "Select a finding",
                subtitle: "Tap a marker, ClinVar variant, or priority to see its details and action plan here."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)
        }
    }
}
#endif
