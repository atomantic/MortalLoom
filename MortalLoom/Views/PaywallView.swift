import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseError: String?

    private let features: [(icon: String, title: String, description: String)] = [
        ("allergens", "Genome Analysis", "ClinVar pathogenicity cross-reference for your DNA"),
        ("chart.line.uptrend.xyaxis", "Blood Marker Insights", "Trend alerts and activity correlation across your lab results"),
        ("clock.badge.checkmark.fill", "Epigenetic Age", "Track biological vs chronological aging over time"),
        ("eye.fill", "Eye Prescription History", "Track vision changes across multiple exams"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    featureList
                    purchaseSection
                    privacyNote
                }
                .padding()
            }
            .background(Color.bg)
            .navigationTitle("MortalLoom Pro")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient.proBrandDiagonal)
            Text("Unlock MortalLoom Pro")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text("One-time purchase. No subscription.")
                .font(.subheadline)
                .foregroundColor(.textMuted)
        }
        .padding(.top, 8)
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(features, id: \.title) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                        Text(feature.description)
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(feature.title): \(feature.description)")
            }
        }
        .background(Color.bgInput)
        .cornerRadius(12)
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if let product = store.proProduct {
                Button {
                    Task {
                        let success = await store.purchase()
                        if success { dismiss() }
                    }
                } label: {
                    HStack {
                        if store.purchaseInProgress {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Unlock Pro \u{2014} \(product.displayPrice)")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient.proBrand)
                    .cornerRadius(12)
                }
                .disabled(store.purchaseInProgress)
                .accessibilityLabel(store.purchaseInProgress ? "Purchase in progress" : "Unlock Pro for \(store.proProduct?.displayPrice ?? "")")
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .accessibilityLabel("Loading purchase options")
            }

            Button("Restore Purchase") {
                Task { await store.restorePurchases() }
            }
            .font(.subheadline)
            .foregroundColor(.textSecondary)

            if let error = purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.danger)
            }
        }
    }

    // MARK: - Privacy

    private var privacyNote: some View {
        Text("Your purchase is processed by Apple. We never see your payment information. No account required.")
            .font(.caption2)
            .foregroundColor(.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }
}
