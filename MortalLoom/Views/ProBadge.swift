import SwiftUI

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(LinearGradient.proBrand)
            .cornerRadius(4)
            .accessibilityLabel("Pro feature")
    }
}

// MARK: - Pro Gate Modifier

struct ProGateModifier: ViewModifier {
    @Environment(StoreManager.self) private var store
    @State private var showingPaywall = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !store.isPro {
                    proOverlay
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
    }

    private var proOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color.purple.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            overlayContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { showingPaywall = true }
        .accessibilityLabel("Unlock with MortalLoom Pro")
        .accessibilityHint("Tap to view upgrade options")
        .accessibilityAddTraits(.isButton)
    }

    private var overlayContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(LinearGradient.proBrandDiagonal)
                Text("MortalLoom Pro")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ProOverlayBullet(icon: "drop.fill",                  text: "Blood markers + genome analysis")
                ProOverlayBullet(icon: "clock.badge.checkmark.fill", text: "Epigenetic age tracking")
                ProOverlayBullet(icon: "figure.stand",               text: "Full body composition + eye tracking")
            }

            Button {
                showingPaywall = true
            } label: {
                Text(store.proProduct.map { "Unlock for \($0.displayPrice)" } ?? "Unlock Pro")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(LinearGradient.proBrand)
                    .cornerRadius(10)
            }

            Text("One-time purchase · No subscription")
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
        .padding(20)
    }
}

private struct ProOverlayBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }
}

extension View {
    func proGated() -> some View {
        modifier(ProGateModifier())
    }
}
