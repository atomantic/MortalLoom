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
            // Disable hit-testing and hide the gated content from the
            // accessibility tree so VoiceOver/keyboard users can't bypass the
            // overlay. The overlay itself is the only interactive element.
            .allowsHitTesting(store.isPro)
            .accessibilityHidden(!store.isPro)
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
                ProOverlayBullet(icon: "allergens",                  text: "Genome + ClinVar analysis")
                ProOverlayBullet(icon: "chart.line.uptrend.xyaxis",  text: "Blood marker trend insights")
                ProOverlayBullet(icon: "clock.badge.checkmark.fill", text: "Epigenetic age tracking")
                ProOverlayBullet(icon: "eye.fill",                   text: "Eye prescription history")
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

struct ProOverlayBullet: View {
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

// MARK: - Pro Teaser Card
//
// Inline upsell card embedded in free-feature views (e.g. between content sections).
// Owns its own paywall sheet so callers don't reimplement the plumbing.

struct ProTeaserCard: View {
    let title: String
    let message: String
    let bullets: [(icon: String, text: String)]
    @State private var showingPaywall = false

    var body: some View {
        Button { showingPaywall = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(LinearGradient.proBrandDiagonal)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    ProBadge()
                }
                Text(message)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 12) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        ProOverlayBullet(icon: bullet.icon, text: bullet.text)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient.proBrandSubtleDiagonal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        // Build a single, complete VoiceOver announcement so non-visual users
        // hear the same context as sighted users (title + message + bullets).
        // Avoid prefixing with "Unlock" since callers may already include it
        // in `title` (e.g. "Unlock Insights" -> "Unlock Unlock…").
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("MortalLoom Pro: \(title)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Tap to view upgrade options")
    }

    private var accessibilityValue: String {
        let bulletText = bullets.map(\.text).joined(separator: ", ")
        return bulletText.isEmpty ? message : "\(message) \(bulletText)."
    }
}
