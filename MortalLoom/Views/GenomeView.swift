import SwiftUI
import UniformTypeIdentifiers

// GenomeVariant is defined in Models/GenomeVariant.swift

// MARK: - GenomeView

struct GenomeView: View {
    @State private var epigeneticTests: [EpigeneticTest] = []
    @State private var sortedEpigeneticTests: [EpigeneticTest] = []
    @State private var showingAddTest = false
    @State private var isLoading = true

    // Genome upload
    @State private var genomeVariants: [GenomeVariant] = []
    @State private var totalVariantCount: Int = 0
    @State private var showingFileImporter = false
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                epigeneticAgeSection
                genomeUploadSection
            }
            .padding()
        }
        .background(Color.bg)
        .sheet(isPresented: $showingAddTest) {
            EpigeneticTestFormView(onSave: { test in
                Task {
                    await DataStore.shared.addEpigeneticTest(test)
                    await loadData()
                }
            })
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .task { await loadData() }
    }

    // MARK: - Epigenetic Age Section

    private var epigeneticAgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Epigenetic Age (\(epigeneticTests.count))")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: { showingAddTest = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }

            if epigeneticTests.isEmpty {
                epigeneticEmptyState
            } else {
                latestEpigeneticCard
                epigeneticHistory
            }
        }
        .padding()
        .cardStyle()
    }

    private var epigeneticEmptyState: some View {
        EmptyStateView(
            icon: "dna",
            title: "No epigenetic age tests recorded.",
            subtitle: "Tap + to add results from TruDiagnostic, GlycanAge, or similar services."
        )
    }

    @ViewBuilder
    private var latestEpigeneticCard: some View {
        if let latest = sortedEpigeneticTests.first {
            VStack(spacing: 12) {
                Text("Latest Test — \(DateFormatting.displayDate(latest.date))")
                    .font(.caption)
                    .foregroundColor(.textMuted)

                HStack(spacing: 24) {
                    ageDisplay(label: "Chronological", age: latest.chronologicalAge)
                    ageDisplay(
                        label: "Biological",
                        age: latest.biologicalAge,
                        color: latest.biologicalAge < latest.chronologicalAge ? .success : .danger
                    )
                }

                if let pace = latest.paceOfAging {
                    HStack(spacing: 4) {
                        Text("Pace of Aging:")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Text(String(format: "%.2f", pace))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(pace < 1.0 ? .success : .danger)
                        Text(pace < 1.0 ? "(slower than average)" : "(faster than average)")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                }

                if let scores = latest.organScores, !scores.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Organ Age Scores")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.textMuted)
                            .textCase(.uppercase)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                        ], spacing: 6) {
                            ForEach(scores.sorted(by: { $0.key < $1.key }), id: \.key) { organ, age in
                                VStack(spacing: 2) {
                                    Text(organ)
                                        .font(.caption2)
                                        .foregroundColor(.textMuted)
                                    Text(String(format: "%.1f", age))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(age < latest.chronologicalAge ? .success : .danger)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background(Color.bgInput)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.bgInput)
            .cornerRadius(8)
        }
    }

    private func ageDisplay(label: String, age: Double, color: Color = .textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.textMuted)
            Text(String(format: "%.1f", age))
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text("years")
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
    }

    @ViewBuilder
    private var epigeneticHistory: some View {
        if sortedEpigeneticTests.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("History")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.textMuted)
                    .textCase(.uppercase)

                ForEach(sortedEpigeneticTests.dropFirst()) { test in
                    HStack {
                        Text(DateFormatting.displayDate(test.date))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text("Chrono: \(String(format: "%.1f", test.chronologicalAge))")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("Bio: \(String(format: "%.1f", test.biologicalAge))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(test.biologicalAge < test.chronologicalAge ? .success : .danger)
                        if let pace = test.paceOfAging {
                            Text("Pace: \(String(format: "%.2f", pace))")
                                .font(.caption)
                                .foregroundColor(pace < 1.0 ? .success : .danger)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(role: .destructive, action: {
                            Task {
                                await DataStore.shared.removeEpigeneticTest(id: test.id)
                                await loadData()
                            }
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Genome Upload Section

    private var genomeUploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genome Data")
                .font(.headline)
                .foregroundColor(.textPrimary)

            if genomeVariants.isEmpty {
                VStack(spacing: 12) {
                    EmptyStateView(
                        icon: "doc.text",
                        title: "Upload raw genome data from 23andMe or AncestryDNA",
                        subtitle: "Supports .txt files with rsID, chromosome, position, and genotype columns. Data stays on your device."
                    )

                    Button(action: { showingFileImporter = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Genome File")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.success)
                        Text(totalVariantCount > genomeVariants.count
                            ? "Showing \(genomeVariants.count) of \(totalVariantCount) total variants"
                            : "\(genomeVariants.count) variants loaded")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Button(action: { showingFileImporter = true }) {
                            Text("Re-import")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }

                    // Show first few variants as preview
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("rsID").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Chr").frame(width: 40, alignment: .center)
                            Text("Pos").frame(width: 80, alignment: .trailing)
                            Text("Genotype").frame(width: 70, alignment: .trailing)
                        }
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.textMuted)
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        Divider()

                        ForEach(genomeVariants.prefix(10)) { variant in
                            HStack(spacing: 0) {
                                Text(variant.rsID)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(variant.chromosome)
                                    .frame(width: 40, alignment: .center)
                                Text(variant.position)
                                    .frame(width: 80, alignment: .trailing)
                                Text(variant.genotype)
                                    .frame(width: 70, alignment: .trailing)
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }

                        if genomeVariants.count > 10 {
                            Text("... and \(genomeVariants.count - 10) more variants")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                                .padding(.top, 4)
                        }
                    }
                }
            }

            if let error = importError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.danger)
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let content = String(data: (try? Data(contentsOf: url)) ?? Data(), encoding: .utf8) else {
                importError = "Could not read file contents."
                return
            }

            let variants = GenomeParser.parse(content)

            if variants.isEmpty {
                importError = "No valid variants found in file. Expected 23andMe or AncestryDNA format."
            } else {
                totalVariantCount = variants.count
                genomeVariants = Array(variants.prefix(1000))
                importError = nil
            }

        case .failure:
            importError = "Failed to select file."
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        let data = await DataStore.shared.getData()
        epigeneticTests = data.epigeneticTests
        sortedEpigeneticTests = data.epigeneticTests.sorted(by: { $0.date > $1.date })
        isLoading = false
    }
}

// MARK: - Epigenetic Test Form

private struct EpigeneticTestFormView: View {
    let onSave: (EpigeneticTest) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var testDate = Date()
    @State private var chronoAge = ""
    @State private var bioAge = ""
    @State private var paceOfAging = ""

    // Common organ scores
    private let organNames = [
        "Heart", "Liver", "Kidney", "Lung", "Brain",
        "Immune", "Metabolic", "Musculoskeletal", "Hormone", "Inflammation",
    ]
    @State private var organScoreValues: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section("Test Date") {
                    DatePicker("Date", selection: $testDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                Section("Age Results") {
                    HStack {
                        Text("Chronological Age")
                            .foregroundColor(.textPrimary)
                        Spacer()
                        TextField("e.g. 40.0", text: $chronoAge)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Biological Age")
                            .foregroundColor(.textPrimary)
                        Spacer()
                        TextField("e.g. 35.0", text: $bioAge)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Pace of Aging")
                            .foregroundColor(.textPrimary)
                        Spacer()
                        TextField("e.g. 0.85", text: $paceOfAging)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("Organ Age Scores (Optional)") {
                    ForEach(organNames, id: \.self) { organ in
                        HStack {
                            Text(organ)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            TextField("—", text: organBinding(for: organ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }
            }
            .navigationTitle("Add Epigenetic Test")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTest() }
                        .disabled(Double(chronoAge) == nil || Double(bioAge) == nil)
                }
            }
        }
    }

    private func organBinding(for organ: String) -> Binding<String> {
        Binding(
            get: { organScoreValues[organ] ?? "" },
            set: { organScoreValues[organ] = $0 }
        )
    }

    private func saveTest() {
        guard let chrono = Double(chronoAge), let bio = Double(bioAge) else { return }
        let dateStr = DateFormatting.dateString( testDate)

        var scores: [String: Double]?
        let parsedScores = organScoreValues.compactMapValues { Double($0) }
        if !parsedScores.isEmpty {
            scores = parsedScores
        }

        let test = EpigeneticTest(
            date: dateStr,
            chronologicalAge: chrono,
            biologicalAge: bio,
            paceOfAging: Double(paceOfAging),
            organScores: scores
        )
        onSave(test)
        dismiss()
    }
}
