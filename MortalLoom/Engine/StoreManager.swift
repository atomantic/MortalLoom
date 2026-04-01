import StoreKit
import CryptoKit
import Security
import os

private let logger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "Store")

@MainActor @Observable
final class StoreManager {
    static let shared = StoreManager()

    private(set) var proProduct: Product?
    private(set) var isPro: Bool = false
    private(set) var purchaseInProgress: Bool = false

    static let proProductID = "net.shadowpuppet.MeatSpaceTracker.pro"

    // SHA-256 of your secret code (lowercase, trimmed).
    // To change: echo -n "yourcode" | shasum -a 256
    private static let secretCodeHash = "2f71e179aa9288130cc255f2a7384d99a1829403444cc3a58ebde15733517f1e"
    private static let secretKeychainKey = "SecretProUnlocked"

    @ObservationIgnored private var transactionListener: Task<Void, Never>?

    private init() {
        if readKeychainFlag(Self.secretKeychainKey) { isPro = true }
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

    // MARK: - Secret Code

    /// Returns true if the code matches the secret. Persists the unlock to Keychain.
    @discardableResult
    func redeemSecretCode(_ code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return false }
        let hash = SHA256.hash(data: Data(normalized.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        guard hex == Self.secretCodeHash else {
            logger.warning("🔑 secret code rejected")
            return false
        }
        writeKeychainFlag(Self.secretKeychainKey, value: true)
        isPro = true
        logger.info("🔓 secret code accepted — Pro unlocked")
        return true
    }

    var hasSecretProUnlock: Bool { readKeychainFlag(Self.secretKeychainKey) }

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
        // Secret code unlock survives entitlement checks
        if !readKeychainFlag(Self.secretKeychainKey) {
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

    // MARK: - Keychain Helpers

    private func readKeychainFlag(_ key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "net.shadowpuppet.MeatSpaceTracker",
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return false }
        return data.first == 1
    }

    private func writeKeychainFlag(_ key: String, value: Bool) {
        let data = Data([value ? 1 : 0])
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "net.shadowpuppet.MeatSpaceTracker",
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
