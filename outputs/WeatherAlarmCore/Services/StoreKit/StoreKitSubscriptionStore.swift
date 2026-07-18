import Combine
import Foundation
import StoreKit

enum WeatherAlarmProductID {
    // TODO: 在 App Store Connect 中创建完全相同的产品 ID。
    // 天气闹钟入门，自动续期订阅，¥19/月。不支持任何代金券/立减券。
    static let weatherMonthly = "com.weatherwake.sub.weather_monthly"

    // 天气闹钟主推订阅，自动续期订阅，¥198/年。不支持任何代金券/立减券。
    static let weatherYearly = "com.weatherwake.sub.weather_yearly"

    // 天气闹钟永久买断优惠价，非消耗型购买，¥298。支持 REF100_OFF / REF50_UNIVERSAL eligibility。
    static let foreverCommute = "com.weatherwake.iap.forever_commute"

    // 天气闹钟永久买断原价，非消耗型购买，¥598。支持 REF100_OFF / REF50_UNIVERSAL eligibility。
    static let foreverWeatherFull = "com.weatherwake.iap.forever_weather_full"

    // 高德路况增强，自动续期订阅，¥19/月。支持 REF50_UNIVERSAL eligibility。
    static let gaodeEnhance = "com.smartwake.sub.path_monthly"

    // 高德路况增强，自动续期订阅，¥198/年。支持 REF50_UNIVERSAL eligibility。
    static let gaodeEnhanceYearly = "com.smartwake.sub.path_yearly"

    // 好友 50 元券对应的真实路径年订阅商品，¥148/年。
    static let pathYearlyFriend50 = "com.smartwake.sub.path_yearly_friend"

    // 好友与邀请人优惠对应真实非消耗型商品，分别为 ¥248 / ¥198。
    static let foreverWeatherFriend50 = "com.smartwake.iap.weather_forever_friend50"
    static let foreverWeatherReferral100 = "com.smartwake.iap.weather_forever_ref100"
    static let foreverWeatherFriend50Regular = "com.smartwake.iap.weather_forever_friend50_regular"
    static let foreverWeatherReferral100Regular = "com.smartwake.iap.weather_forever_ref100_regular"

    // TODO: 在 App Store Connect 中创建 3 个非消耗型众筹产品：AI 催眠 ¥98，其余两个 ¥20。
    // AI 催眠引导睡眠众筹，开发完成后可抵扣对应正式功能价格。
    static let crowdfundSleepAI = "com.weatherwake.iap.crowdfund.sleep_ai"

    // 天气外卖提醒众筹，开发完成后可抵扣对应正式功能价格。
    static let crowdfundWeatherTakeout = "com.weatherwake.iap.crowdfund.weather_takeout"

    // 明天天气提前睡觉闹钟众筹，开发完成后可抵扣对应正式功能价格。
    static let crowdfundEarlySleepAlarm = "com.weatherwake.iap.crowdfund.early_sleep_alarm"

    static let crowdfundingProducts = [
        crowdfundSleepAI,
        crowdfundWeatherTakeout,
        crowdfundEarlySleepAlarm
    ]

    static let all = [
        weatherMonthly,
        weatherYearly,
        foreverCommute,
        foreverWeatherFull,
        gaodeEnhance,
        gaodeEnhanceYearly,
        pathYearlyFriend50,
        foreverWeatherFriend50,
        foreverWeatherReferral100,
        foreverWeatherFriend50Regular,
        foreverWeatherReferral100Regular,
        crowdfundSleepAI,
        crowdfundWeatherTakeout,
        crowdfundEarlySleepAlarm
    ]

    static let weatherAccessProducts = [
        weatherMonthly,
        weatherYearly,
        foreverCommute,
        foreverWeatherFull,
        foreverWeatherFriend50,
        foreverWeatherReferral100,
        foreverWeatherFriend50Regular,
        foreverWeatherReferral100Regular
    ]

    static let pathAccessProducts = [gaodeEnhance, gaodeEnhanceYearly, pathYearlyFriend50]
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
    /// TestFlight convenience build: unlock all paid feature gates so device testing can
    /// focus on WeatherKit, AMap, AlarmKit, and UI flows before App Store products are finalized.
    /// This does not mock WeatherKit or route API responses; it only bypasses StoreKit gating.
    #if SMARTWAKE_ALL_PAID_TEST
    private static let unlockAllFeaturesForTestFlight = true
    #else
    private static let unlockAllFeaturesForTestFlight = false
    #endif

    @Published private(set) var products: [Product] = []
    @Published private(set) var hasPremiumAccess = false
    @Published private(set) var hasPurchasedForever = false
    @Published private(set) var isWeatherSubscribed = false
    @Published private(set) var hasGaodeEnhance = false
    @Published private(set) var activeEntitlementProductIDs: Set<String> = []
    @Published private(set) var supportedCrowdfundingProductIDs: Set<String> = []
    @Published private(set) var state: PurchaseState = .idle

    private var updatesTask: Task<Void, Never>?
    private var productsLoadTask: Task<Void, Never>?
    private let referralStateStore: ReferralStateStore
    private let snapshotStore: PurchaseEntitlementSnapshotStore

    init(
        referralStateStore: ReferralStateStore = ReferralStateStore(),
        snapshotStore: PurchaseEntitlementSnapshotStore = PurchaseEntitlementSnapshotStore()
    ) {
        self.referralStateStore = referralStateStore
        self.snapshotStore = snapshotStore
        if Self.unlockAllFeaturesForTestFlight {
            hasPremiumAccess = true
            hasPurchasedForever = true
            isWeatherSubscribed = true
            hasGaodeEnhance = true
            activeEntitlementProductIDs = [
                WeatherAlarmProductID.weatherYearly,
                WeatherAlarmProductID.gaodeEnhanceYearly,
                WeatherAlarmProductID.foreverWeatherFull
            ]
            supportedCrowdfundingProductIDs = Set(WeatherAlarmProductID.crowdfundingProducts)
        }
        updatesTask = observeTransactionUpdates()
    }

    var hasSubscriptionPlanShorterThanSixMonths: Bool {
        activeEntitlementProductIDs.contains(WeatherAlarmProductID.weatherMonthly)
            || activeEntitlementProductIDs.contains(WeatherAlarmProductID.gaodeEnhance)
    }

    func startLoadingProductsAndEntitlements() {
        guard productsLoadTask == nil else {
            return
        }

        productsLoadTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.loadProductsAndEntitlements()
            self.productsLoadTask = nil
        }
    }

    func loadProductsAndEntitlements() async {
        guard state != .loading else {
            return
        }

        state = .loading

        if Self.unlockAllFeaturesForTestFlight {
            do {
                products = try await Product.products(for: WeatherAlarmProductID.all)
                    .sorted { left, right in
                        sortIndex(for: left.id) < sortIndex(for: right.id)
                    }
            } catch {
                products = []
            }
            await refreshEntitlements()
            state = .idle
            return
        }

        do {
            products = try await Product.products(for: WeatherAlarmProductID.all)
                .sorted { left, right in
                    sortIndex(for: left.id) < sortIndex(for: right.id)
                }

            await refreshEntitlements()
            state = .idle
        } catch {
            await refreshEntitlements()
            state = .failed("购买服务暂时没有响应，轻点任一方案即可重新连接。")
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        state = .purchasing

        do {
            let result: Product.PurchaseResult
            if let referrerID = referralStateStore.referrerID {
                result = try await product.purchase(options: [.appAccountToken(referrerID)])
            } else {
                result = try await product.purchase()
            }

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshEntitlements()
                await transaction.finish()
                state = .idle
                return true
            case .userCancelled:
                state = .idle
                return false
            case .pending:
                state = .failed("购买待确认")
                return false
            @unknown default:
                state = .failed("未知购买状态")
                return false
            }
        } catch {
            state = .failed("购买失败")
            return false
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
                    if transaction.revocationDate != nil {
                        await self.refreshEntitlements(allowSnapshotFallback: false)
                        await transaction.finish()
                        continue
                    }

                    await self.refreshEntitlements()
                    await transaction.finish()
                } catch {
                    // 单个未通过验证或暂时无法读取的更新不能反向清空已经验证过的权益。
                    // 下一次 StoreKit 刷新或用户主动恢复购买时再重新核验。
                    continue
                }
            }
        }
    }

    private func refreshEntitlements(allowSnapshotFallback: Bool = true) async {
        if Self.unlockAllFeaturesForTestFlight {
            hasPurchasedForever = true
            isWeatherSubscribed = true
            hasGaodeEnhance = true
            hasPremiumAccess = true
            activeEntitlementProductIDs = [
                WeatherAlarmProductID.weatherYearly,
                WeatherAlarmProductID.gaodeEnhanceYearly,
                WeatherAlarmProductID.foreverWeatherFull
            ]
            supportedCrowdfundingProductIDs = Set(WeatherAlarmProductID.crowdfundingProducts)
            return
        }

        var ownsForever = false
        var ownsWeatherSubscription = false
        var ownsGaodeEnhance = false
        var supportedCrowdfundingProductIDs = Set<String>()
        var weatherExpireDate: Date?
        var gaodeExpireDate: Date?
        var entitlementProductIDs = Set<String>()
        var entitlementTransactionIDs = Set<String>()
        var entitlementOriginalTransactionIDs = Set<String>()

        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(entitlement) else {
                continue
            }

            entitlementProductIDs.insert(transaction.productID)
            entitlementTransactionIDs.insert(String(transaction.id))
            entitlementOriginalTransactionIDs.insert(String(transaction.originalID))

            switch transaction.productID {
            case WeatherAlarmProductID.foreverCommute,
                 WeatherAlarmProductID.foreverWeatherFull,
                 WeatherAlarmProductID.foreverWeatherFriend50,
                 WeatherAlarmProductID.foreverWeatherReferral100,
                 WeatherAlarmProductID.foreverWeatherFriend50Regular,
                 WeatherAlarmProductID.foreverWeatherReferral100Regular:
                ownsForever = true
            case WeatherAlarmProductID.weatherMonthly, WeatherAlarmProductID.weatherYearly:
                ownsWeatherSubscription = true
                weatherExpireDate = transaction.expirationDate
            case WeatherAlarmProductID.gaodeEnhance,
                 WeatherAlarmProductID.gaodeEnhanceYearly,
                 WeatherAlarmProductID.pathYearlyFriend50:
                ownsGaodeEnhance = true
                gaodeExpireDate = transaction.expirationDate
            case WeatherAlarmProductID.crowdfundSleepAI,
                 WeatherAlarmProductID.crowdfundWeatherTakeout,
                 WeatherAlarmProductID.crowdfundEarlySleepAlarm:
                supportedCrowdfundingProductIDs.insert(transaction.productID)
            default:
                continue
            }
        }

        hasPurchasedForever = ownsForever
        isWeatherSubscribed = ownsWeatherSubscription
        hasGaodeEnhance = ownsGaodeEnhance
        activeEntitlementProductIDs = entitlementProductIDs
        self.supportedCrowdfundingProductIDs = supportedCrowdfundingProductIDs
        hasPremiumAccess = ownsForever || ownsWeatherSubscription

        if !hasPremiumAccess,
           !hasGaodeEnhance,
           allowSnapshotFallback,
           snapshotStore.hasVerifiedPurchaseEvidence {
            hasPurchasedForever = snapshotStore.databaseSyncSnapshot.hasPurchasedForever
            isWeatherSubscribed = snapshotStore.canUseWeather && !hasPurchasedForever
            hasGaodeEnhance = snapshotStore.canUseGaode
            hasPremiumAccess = snapshotStore.canUseWeather
            snapshotStore.markNeedsRestoreWarning()
            return
        }

        snapshotStore.saveSnapshot(
            hasPurchasedForever: ownsForever,
            isWeatherSubscribed: ownsWeatherSubscription,
            hasGaodeEnhance: ownsGaodeEnhance,
            weatherExpireDate: weatherExpireDate,
            gaodeExpireDate: gaodeExpireDate,
            productIDs: entitlementProductIDs,
            transactionIDs: entitlementTransactionIDs,
            originalTransactionIDs: entitlementOriginalTransactionIDs
        )

        if !hasPremiumAccess && !hasGaodeEnhance {
            await LocalWakeNotificationScheduler().removePaidFeatureNotifications()
            try? await AlarmManager().ensureAllBasicAlarmsRegistered()
        } else if hasPremiumAccess {
            LocalWakeNotificationScheduler().removeWeatherUpgradeReminder()
        }
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
