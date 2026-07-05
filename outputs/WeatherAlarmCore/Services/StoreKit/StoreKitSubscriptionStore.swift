import Combine
import Foundation
import StoreKit

enum WeatherAlarmProductID {
    // TODO: 在 App Store Connect 中创建完全相同的产品 ID。
    // 月费 5 元：自动续期订阅
    static let monthly = "com.domenwang.weatheralarm.pro.monthly"

    // 年费 50 元：自动续期订阅
    static let yearly = "com.domenwang.weatheralarm.pro.yearly"

    // 永久 198 元：非消耗型购买
    static let lifetime = "com.domenwang.weatheralarm.pro.lifetime"

    static let all = [monthly, yearly, lifetime]
}

enum PurchaseState: Equatable {
    case idle
    case loading
    case purchasing
    case failed(String)
}

enum StoreKitSubscriptionError: Error {
    case failedVerification
}

/// StoreKit 2 订阅/购买管理器。
///
/// 这里不会伪造订阅成功。只有 StoreKit 返回 verified transaction 时，
/// `hasPremiumAccess` 才会变成 true，智能天气调整开关才能启用。
@MainActor
final class StoreKitSubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var hasPremiumAccess = false
    @Published private(set) var state: PurchaseState = .idle

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()
    }

    func loadProductsAndEntitlements() async {
        state = .loading

        do {
            products = try await Product.products(for: WeatherAlarmProductID.all)
                .sorted { left, right in
                    sortIndex(for: left.id) < sortIndex(for: right.id)
                }

            await refreshEntitlements()
            state = .idle
        } catch {
            state = .failed("订阅信息加载失败")
        }
    }

    func purchase(_ product: Product) async {
        state = .purchasing

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshEntitlements()
                await transaction.finish()
                state = .idle
            case .userCancelled:
                state = .idle
            case .pending:
                state = .failed("购买待确认")
            @unknown default:
                state = .failed("未知购买状态")
            }
        } catch {
            state = .failed("购买失败")
        }
    }

    func restorePurchases() async {
        state = .loading

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            state = .idle
        } catch {
            state = .failed("恢复购买失败")
        }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else {
                    return
                }

                do {
                    let transaction = try self.checkVerified(update)
                    await self.refreshEntitlements()
                    await transaction.finish()
                } catch {
                    self.hasPremiumAccess = false
                }
            }
        }
    }

    private func refreshEntitlements() async {
        var isEntitled = false

        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(entitlement) else {
                continue
            }

            if WeatherAlarmProductID.all.contains(transaction.productID) {
                isEntitled = true
                break
            }
        }

        hasPremiumAccess = isEntitled
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreKitSubscriptionError.failedVerification
        }
    }

    private func sortIndex(for productID: String) -> Int {
        WeatherAlarmProductID.all.firstIndex(of: productID) ?? Int.max
    }
}
