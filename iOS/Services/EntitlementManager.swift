import CryptoKit
import Foundation
import StoreKit

/// Owns the "free for 14 days, then one-time unlock" gate.
///
/// Trial start date is persisted in both `UserDefaults` (local) and
/// `NSUbiquitousKeyValueStore` (iCloud key-value store). On every launch
/// we take the *earlier* of the two values so deleting/reinstalling the
/// app does not reset the trial as long as the user stays signed in to
/// the same Apple ID.
///
/// Purchase state comes from StoreKit 2 `Transaction.currentEntitlements`,
/// not from local persistence — Apple's own transaction store is the
/// source of truth and survives reinstall on its own.
@MainActor
final class EntitlementManager: ObservableObject {
    static let productID = "com.elbaeverywhere.eeaccess.lifetime"
    static let trialDuration: TimeInterval = 14 * 24 * 60 * 60   // 14 days
    private static let installDateKey = "EEAccess.installDate"
    private static let compedKey = "EEAccess.compedUnlock"

    /// SHA-256 (lowercase hex) of valid in-app access codes, matched against the
    /// UPPERCASED entered code (so codes are case-insensitive). Stored as hashes
    /// so the plaintext codes can't be pulled out of the binary with `strings`.
    /// Add a code by hashing it: `printf '%s' "YOURCODE" | shasum -a 256`
    private static let validCodeHashes: Set<String> = [
        "2071224ff7727964c423b492f6c0f99f97a1cf3fd6991eb5b87fd98247a363f0", // EUNAOSEI
    ]

    @Published private(set) var isPurchased: Bool = false
    @Published private(set) var product: Product?
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isSandboxBuild: Bool = false
    /// Unlocked via an in-app access code (free comp, granted outside StoreKit).
    @Published private(set) var isComped: Bool = false
    @Published var lastError: String?

    private(set) var installDate: Date
    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        let local = UserDefaults.standard.object(forKey: Self.installDateKey) as? Date
        let cloud = NSUbiquitousKeyValueStore.default.object(forKey: Self.installDateKey) as? Date
        let resolved = [local, cloud].compactMap { $0 }.min() ?? Date.now
        self.installDate = resolved

        UserDefaults.standard.set(resolved, forKey: Self.installDateKey)
        NSUbiquitousKeyValueStore.default.set(resolved, forKey: Self.installDateKey)
        NSUbiquitousKeyValueStore.default.synchronize()

        // Synchronous best-effort so TestFlight / App Review builds are unlocked
        // on the FIRST frame (no paywall flash). detectSandbox() then confirms
        // and refines it via AppTransaction once StoreKit is ready.
        isSandboxBuild = Self.hasSandboxReceipt
        isComped = UserDefaults.standard.bool(forKey: Self.compedKey)

        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }

        Task { [weak self] in
            await self?.detectSandbox()
        }
    }

    deinit { transactionUpdatesTask?.cancel() }

    // MARK: Trial state

    var trialEndDate: Date {
        installDate.addingTimeInterval(Self.trialDuration)
    }

    var daysLeftInTrial: Int {
        let seconds = trialEndDate.timeIntervalSinceNow
        return max(0, Int(ceil(seconds / 86_400)))
    }

    var isInTrial: Bool {
        Date.now < trialEndDate
    }

    /// True when the user can use the app — paid, still in trial, a TestFlight /
    /// App Store review build, or any build run from Xcode.
    ///
    /// `#if DEBUG` guarantees that builds you run directly from Xcode (the
    /// default Run action is Debug) are always unlocked for testing — without
    /// it, an Xcode build reports the `.xcode` StoreKit environment (not
    /// `.sandbox`) and would hit the expired trial. App Store and TestFlight
    /// builds are always Release, so this never unlocks production.
    var isEntitled: Bool {
        #if DEBUG
        return true
        #else
        return isPurchased || isComped || isInTrial || isSandboxBuild
        #endif
    }

    /// Redeems an in-app access code you hand out for free (e.g. promotional
    /// codes for selected users). Unlocks the app directly, outside StoreKit —
    /// for free comps, not for selling. The unlock persists on this device.
    /// Returns `true` if the code was valid.
    @discardableResult
    func redeem(code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return false }
        let hex = SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }.joined()
        guard Self.validCodeHashes.contains(hex) else { return false }
        isComped = true
        UserDefaults.standard.set(true, forKey: Self.compedKey)
        return true
    }

    /// TestFlight and App Store review run against the *sandbox* App Store
    /// environment. Treat those builds as fully entitled so testers and
    /// reviewers aren't blocked by an expired trial — which can happen
    /// because the trial start is inherited via iCloud from a prior App Store
    /// install. `Bundle.main.appStoreReceiptURL` is deprecated in iOS 18; the
    /// modern check is `AppTransaction.shared.environment`.
    /// Synchronous TestFlight / App-Review signal: those builds ship a sandbox
    /// receipt. `appStoreReceiptURL` is deprecated but is the only *synchronous*
    /// option, and gating the launch screen can't wait on an async call without
    /// flashing the paywall; `detectSandbox()` confirms it via AppTransaction.
    private static var hasSandboxReceipt: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private func detectSandbox() async {
        do {
            let result = try await AppTransaction.shared
            if case .verified(let appTransaction) = result {
                // .sandbox = TestFlight / App Review; .xcode = run from Xcode
                // (incl. StoreKit testing) — both are non-production test builds.
                let env = appTransaction.environment
                await MainActor.run {
                    self.isSandboxBuild = env == .sandbox || env == .xcode
                }
            }
        } catch {
            // Not fatal — a missing/uninitialized AppTransaction (e.g. running
            // before StoreKit has any receipt to verify) just means we treat
            // the build as production. Trial gate still applies.
        }
    }

    // MARK: StoreKit

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            self.product = products.first
        } catch {
            self.lastError = "Couldn't load product: \(error.localizedDescription)"
        }
    }

    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result, txn.productID == Self.productID {
                entitled = true
            }
        }
        self.isPurchased = entitled
    }

    func purchase() async {
        guard let product else {
            lastError = "Product not loaded yet."
            return
        }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        lastError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled:
                break
            case .pending:
                lastError = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isPurchased {
                lastError = "No prior purchase found for this Apple ID."
            }
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Redemption note: the `…lifetime` product is a non-consumable, so codes
    /// distributed for it are App Store **promo codes** (offer codes exist only
    /// for subscriptions). Promo codes are redeemed in the App Store app, so the
    /// paywall's "Redeem Code" button opens `apps.apple.com/redeem` rather than
    /// the in-app `AppStore.presentOfferCodeRedeemSheet(in:)`. A redemption then
    /// arrives through the `Transaction.updates` listener and flips
    /// `isPurchased`.

    private func handle(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let txn):
            if txn.productID == Self.productID {
                isPurchased = true
                await txn.finish()
            }
        case .unverified(_, let error):
            lastError = "Transaction unverified: \(error.localizedDescription)"
        }
    }
}
