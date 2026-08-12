import SwiftUI

// MARK: - Donation Type Color

extension DonationType {
    var color: Color {
        switch self {
        case .wholeBlood: .red
        case .plasma: .yellow
        case .platelets: .orange
        }
    }
}

// MARK: - BloodDonationsView

/// Donation tracker: when you gave, which product, and how much. Leads with
/// the eligibility readout (the question a donor actually asks — "can I give
/// yet?"), then lifetime/rolling-year totals, the log form, and history.
struct BloodDonationsView: View {
    @State private var donations: [BloodDonation] = []

    // Log form
    @State private var formType: DonationType = .wholeBlood
    @State private var formVolume = "\(DonationType.wholeBlood.defaultVolumeML)"
    @State private var formDate = Date()
    @State private var formLocation = ""

    // Edit sheet
    @State private var editingDonation: BloodDonation?
    @State private var editType: DonationType = .wholeBlood
    @State private var editVolume = ""
    @State private var editDate = Date()
    @State private var editLocation = ""
    @State private var showDeleteConfirm = false

    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                eligibilityCard
                if donations.isEmpty {
                    emptyState
                } else {
                    statsBar
                }
                logForm
                history
            }
            .padding()
        }
        .background(Color.bg)
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
        .sheet(item: $editingDonation) { donation in
            editSheet(donation)
        }
        .toast($toastMessage)
    }

    // MARK: - Data

    private func loadData() async {
        donations = await DataStore.shared.getData().bloodDonations
    }

    // MARK: - Eligibility

    private var eligibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "ELIGIBILITY")

            ForEach(DonationType.allCases, id: \.self) { type in
                eligibilityRow(type)
            }

            Text("Same-product intervals based on US Red Cross guidance (whole blood 56 days, plasma 28, platelets 7). Your donor centre has the final say — especially if you mix products.")
                .font(.caption2)
                .foregroundColor(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .cardStyle()
    }

    private func eligibilityRow(_ type: DonationType) -> some View {
        let days = DonationEngine.daysUntilEligible(donations, type: type)
        // Count from the rolling year rather than back-deriving it from the
        // clamped remainder, so a donor over the cap reads "7 of 6", not "6 of 6".
        let used = DonationEngine.inRollingYear(donations, type: type).count
        let remaining = DonationEngine.remaining(inYear: used, type: type)
        let status = eligibilityStatus(days: days, remaining: remaining)
        let ready = days == 0 && remaining > 0

        return HStack(spacing: 10) {
            Image(systemName: type.icon)
                .font(.body)
                .foregroundColor(type.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(type.label)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                Text("\(used) of \(type.maxDonationsPerYear) in the past year")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }

            Spacer()

            Text(status)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(ready ? .success : .warning)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.label): \(status). \(used) of \(type.maxDonationsPerYear) donations in the past year.")
    }

    /// The annual cap can bind even when the deferral window has passed, so
    /// check it first — "eligible now" would be wrong for a donor who's at
    /// their yearly limit.
    private func eligibilityStatus(days: Int, remaining: Int) -> String {
        if remaining == 0 { return "Annual limit reached" }
        if days == 0 { return "Eligible now" }
        return days == 1 ? "In 1 day" : "In \(days) days"
    }

    // MARK: - Stats

    private var statsBar: some View {
        let yearDonations = DonationEngine.inRollingYear(donations)
        let counts = DonationEngine.countsByType(donations)

        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                substanceStatItem(label: "Lifetime", value: "\(donations.count)")
                Divider().frame(height: 40)
                substanceStatItem(
                    label: "Total Volume",
                    value: DonationEngine.formatVolume(DonationEngine.totalVolumeML(donations))
                )
            }
            HStack(spacing: 0) {
                substanceStatItem(label: "Past Year", value: "\(yearDonations.count)")
                Divider().frame(height: 40)
                substanceStatItem(
                    label: "Year Volume",
                    value: DonationEngine.formatVolume(DonationEngine.totalVolumeML(yearDonations))
                )
            }
            if counts.count > 1 {
                HStack(spacing: 0) {
                    ForEach(counts, id: \.type) { entry in
                        substanceStatItem(
                            label: entry.type.label,
                            value: "\(entry.count)",
                            valueColor: entry.type.color
                        )
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "drop.fill",
            title: "No donations logged.",
            subtitle: "Log one below to start tracking volume and eligibility."
        )
        .cardStyle()
    }

    // MARK: - Log Form

    private var logForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "LOG DONATION")

            VStack(spacing: 10) {
                Picker("Type", selection: $formType) {
                    ForEach(DonationType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: formType) { _, newType in
                    formVolume = "\(newType.defaultVolumeML)"
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Volume (mL)")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                    TextField("Volume", text: $formVolume)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityLabel("Volume in millilitres")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Location (optional)")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                    TextField("Where you donated", text: $formLocation)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Donation location")
                }

                DatePicker("Date", selection: $formDate, in: ...Date(), displayedComponents: .date)
                    .font(.subheadline)

                Button {
                    Task { await addDonation() }
                } label: {
                    Text("Log Donation")
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(Int(formVolume) == nil)
            }
            .padding()
            .cardStyle()
        }
    }

    // MARK: - History

    @ViewBuilder
    private var history: some View {
        let sorted = donations.sorted { $0.date > $1.date }

        if !sorted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "HISTORY")
                LazyVStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Date").frame(width: 80, alignment: .leading)
                        Text("Type").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Volume").frame(width: 70, alignment: .trailing)
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, donation in
                        donationRow(donation, rowIndex: index)
                    }
                }
            }
        }
    }

    private func donationRow(_ donation: BloodDonation, rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            Text(substanceDisplayDate(donation.date))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: donation.donationType.icon)
                    .font(.caption2)
                    .foregroundColor(donation.donationType.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(donation.donationType.label)
                    if !donation.location.isEmpty {
                        Text(donation.location)
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(donation.volumeML) mL")
                .frame(width: 70, alignment: .trailing)
        }
        .modifier(SubstanceRowChrome(
            rowIndex: rowIndex,
            accessibilityLabel: accessibilityLabel(donation),
            onEdit: { startEditing(donation) },
            onDelete: {
                Task {
                    await DataStore.shared.removeBloodDonation(id: donation.id)
                    await loadData()
                }
            }
        ))
    }

    private func accessibilityLabel(_ donation: BloodDonation) -> String {
        let base = "\(donation.donationType.label) donation, \(donation.volumeML) millilitres, \(substanceDisplayDate(donation.date))"
        return donation.location.isEmpty ? base : "\(base), at \(donation.location)"
    }

    // MARK: - Edit Sheet

    private func startEditing(_ donation: BloodDonation) {
        editType = donation.donationType
        editVolume = "\(donation.volumeML)"
        editDate = DateFormatting.dateFromString(donation.date) ?? Date()
        editLocation = donation.location
        editingDonation = donation
    }

    private func editSheet(_ donation: BloodDonation) -> some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $editType) {
                    ForEach(DonationType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                TextField("Volume (mL)", text: $editVolume)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("Location", text: $editLocation)
                DatePicker("Date", selection: $editDate, in: ...Date(), displayedComponents: .date)

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Donation", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .macGroupedFormStyle()
            .macSheetFrame(minHeight: 360, idealHeight: 480)
            .navigationTitle("Edit Donation")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingDonation = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let volume = Int(editVolume) else { return }
                        let updated = BloodDonation(
                            id: donation.id,
                            donationType: editType,
                            volumeML: volume,
                            date: DateFormatting.dateString(editDate),
                            location: editLocation.trimmingCharacters(in: .whitespaces)
                        )
                        Task {
                            await DataStore.shared.updateBloodDonation(updated)
                            await loadData()
                        }
                        editingDonation = nil
                    }
                    .disabled(Int(editVolume) == nil)
                }
            }
            .alert("Delete Donation", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        await DataStore.shared.removeBloodDonation(id: donation.id)
                        await loadData()
                    }
                    editingDonation = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this donation?")
            }
        }
    }

    // MARK: - Actions

    private func addDonation() async {
        guard let volume = Int(formVolume) else { return }
        let donation = BloodDonation(
            donationType: formType,
            volumeML: volume,
            date: DateFormatting.dateString(formDate),
            location: formLocation.trimmingCharacters(in: .whitespaces)
        )
        await DataStore.shared.addBloodDonation(donation)
        formVolume = "\(formType.defaultVolumeML)"
        formLocation = ""
        formDate = Date()
        await loadData()
        showToast($toastMessage, message: "\(formType.label) donation logged")
    }
}
