import SwiftUI

/// The "Bio Age" tab of the Genome screen: epigenetic-age test entry, the
/// latest-test summary card, and historical results. Pure presentation backed
/// by `GenomeViewModel` (extracted from `GenomeView`, issue #24).
struct EpigeneticAgeView: View {
    @Bindable var vm: GenomeViewModel
    @Binding var showingAddTest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Epigenetic Age")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                CitationBadge(
                    ids: [
                        CitationLibrary.horvathClock2013.id,
                        CitationLibrary.dunedinPace2022.id,
                    ],
                    claim: "DNA-methylation biological age and pace-of-aging"
                )
                if vm.epigeneticTests.count > 1 {
                    Text("\(vm.epigeneticTests.count) tests")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
                Spacer()
                Button(action: { showingAddTest = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .accessibilityLabel("Add epigenetic age test")
            }

            if vm.epigeneticTests.isEmpty {
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
        if let latest = vm.sortedEpigeneticTests.first {
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
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(organ) age: \(String(format: "%.1f", age)) years, \(age < latest.chronologicalAge ? "younger than chronological" : "older than chronological")")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) age: \(String(format: "%.1f", age)) years")
    }

    @ViewBuilder
    private var epigeneticHistory: some View {
        if vm.sortedEpigeneticTests.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("History")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.textMuted)
                    .textCase(.uppercase)

                ForEach(vm.sortedEpigeneticTests.dropFirst()) { test in
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
                            Task { await vm.removeEpigeneticTest(id: test.id) }
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Epigenetic Test Form

struct EpigeneticTestFormView: View {
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
            .macGroupedFormStyle()
            .navigationTitle("Add Epigenetic Test")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .macSheetFrame()
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
        let dateStr = DateFormatting.dateString(testDate)

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
