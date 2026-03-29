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

    private init() {
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
            logger.info("🛒 loaded \(products.count) products")
        } catch {
            logger.error("🛒 failed to load products: \(error.localizedDescription)")
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
            logger.error("🛒 purchase failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkEntitlements()
            logger.info("🛒 restore complete isPro=\(self.isPro)")
        } catch {
            logger.error("🛒 restore failed: \(error.localizedDescription)")
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
        isPro = false
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
