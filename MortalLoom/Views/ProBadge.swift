import SwiftUI

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                LinearGradient(
                    colors: [.accentColor, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(4)
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
                    Color.bg.opacity(0.8)
                        .overlay {
                            VStack(spacing: 12) {
                                ProBadge()
                                Text("Unlock with Pro")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .onTapGesture { showingPaywall = true }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
    }
}

extension View {
    func proGated() -> some View {
        modifier(ProGateModifier())
    }
}
