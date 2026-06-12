import StoreKit
import os

private let logger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "Store")

@MainActor @Observable
final class StoreManager {
    static let shared = StoreManager()

    private(set) var proProduct: Product?
    private(set) var isPro: Bool = false
    private(set) var purchaseInProgress: Bool = false

    static let proProductID = "net.shadowpuppet.MeatSpaceTracker.pro"

    @ObservationIgnored private var transactionListener: Task<Void, Never>?
    /// Debug-only launch flag for screenshot/UI testing builds. Release binaries
    /// ignore this flag so the App Store binary cannot be tricked into bypassing
    /// the IAP via launch arguments.
    private let forceProEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-force-pro")
        #else
        return false
        #endif
    }()

    private init() {
        if forceProEnabled { isPro = true }
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await checkEntitlements() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
            logger.info("🛒 loaded \(products.count, privacy: .public) products")
        } catch {
            logger.error("🛒 failed to load products: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Purchase

    func purchase() async -> Bool {
        guard let product = proProduct else {
            logger.warning("🛒 no product available to purchase")
            return false
        }
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isPro = true
                logger.info("🛒 purchase successful")
                return true
            case .userCancelled:
                logger.info("🛒 purchase cancelled by user")
                return false
            case .pending:
                logger.info("🛒 purchase pending approval")
                return false
            @unknown default:
                return false
            }
        } catch {
            logger.error("🛒 purchase failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkEntitlements()
            logger.info("🛒 restore complete isPro=\(self.isPro, privacy: .public)")
        } catch {
            logger.error("🛒 restore failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Entitlements

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                isPro = true
                return
            }
        }
        if !forceProEnabled {
            isPro = false
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.checkEntitlements()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }
}
