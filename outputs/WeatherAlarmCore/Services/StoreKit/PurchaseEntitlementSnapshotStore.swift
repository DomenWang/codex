import Foundation

struct PurchaseEntitlementSnapshot: Codable, Equatable, Sendable {
    let hasPurchasedForever: Bool
    let isWeatherSubscribed: Bool
    let hasGaodeEnhance: Bool
    let weatherExpireDate: Date?
    let gaodeExpireDate: Date?
    let productIDs: [String]
    let transactionIDs: [String]
    let originalTransactionIDs: [String]
    let capturedAt: Date?

    var hasAnyEntitlement: Bool {
        hasPurchasedForever || isWeatherSubscribed || hasGaodeEnhance
    }

    var hasVerifiedPurchaseEvidence: Bool {
        !transactionIDs.isEmpty || !originalTransactionIDs.isEmpty
    }
}

/// 购买权限的本地快照。
///
/// 后台任务不应该依赖实时 StoreKit 查询，因为 Apple ID “媒体与购买”登出、
/// 网络异常或系统后台时间过短，都可能让实时校验暂时失败。购买/恢复购买成功后，
/// StoreKit 层会把 verified transaction 固化到这里；后台任务只读这个快照做决策。
///
/// 账号系统上线后，这份快照也是同步用户数据库的客户端来源。登录/购买/恢复购买时
/// 可以把它上传到后端；同步失败不能反向清空本地权益，避免已支付用户因为网络或
/// 登录系统迁移而丢失功能。
final class PurchaseEntitlementSnapshotStore {
    #if SMARTWAKE_ALL_PAID_TEST
    private static let unlockAllFeaturesForTesting = true
    #else
    private static let unlockAllFeaturesForTesting = false
    #endif

    private enum Keys {
        static let hasPurchasedForever = "ww_hasPurchasedForever"
        static let isWeatherSubscribed = "ww_isWeatherSubscribed"
        static let hasGaodeEnhance = "ww_hasGaodeEnhance"
        static let purchaseTimestamp = "ww_purchase_timestamp"
        static let weatherExpireDate = "ww_weather_expire_date"
        static let gaodeExpireDate = "ww_gaode_expire_date"
        static let needsRestoreWarning = "ww_needsRestoreWarning"
        static let productIDs = "ww_purchase_product_ids"
        static let transactionIDs = "ww_purchase_transaction_ids"
        static let originalTransactionIDs = "ww_purchase_original_transaction_ids"
        static let lastDatabaseSyncDate = "ww_purchase_last_database_sync_date"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var canUseWeather: Bool {
        if Self.unlockAllFeaturesForTesting {
            return true
        }

        if userDefaults.bool(forKey: Keys.hasPurchasedForever) {
            return true
        }

        return Self.subscriptionIsActive(
            storedFlag: userDefaults.bool(forKey: Keys.isWeatherSubscribed),
            expirationDate: userDefaults.object(forKey: Keys.weatherExpireDate) as? Date
        )
    }

    var canUseGaode: Bool {
        if Self.unlockAllFeaturesForTesting {
            return true
        }

        return Self.subscriptionIsActive(
            storedFlag: userDefaults.bool(forKey: Keys.hasGaodeEnhance),
            expirationDate: userDefaults.object(forKey: Keys.gaodeExpireDate) as? Date
        )
    }

    static func subscriptionIsActive(
        storedFlag: Bool,
        expirationDate: Date?,
        now: Date = Date()
    ) -> Bool {
        expirationDate.map { $0 > now } ?? storedFlag
    }

    var needsRestoreWarning: Bool {
        userDefaults.bool(forKey: Keys.needsRestoreWarning)
    }

    var databaseSyncSnapshot: PurchaseEntitlementSnapshot {
        PurchaseEntitlementSnapshot(
            hasPurchasedForever: userDefaults.bool(forKey: Keys.hasPurchasedForever),
            isWeatherSubscribed: userDefaults.bool(forKey: Keys.isWeatherSubscribed),
            hasGaodeEnhance: userDefaults.bool(forKey: Keys.hasGaodeEnhance),
            weatherExpireDate: userDefaults.object(forKey: Keys.weatherExpireDate) as? Date,
            gaodeExpireDate: userDefaults.object(forKey: Keys.gaodeExpireDate) as? Date,
            productIDs: userDefaults.stringArray(forKey: Keys.productIDs) ?? [],
            transactionIDs: userDefaults.stringArray(forKey: Keys.transactionIDs) ?? [],
            originalTransactionIDs: userDefaults.stringArray(forKey: Keys.originalTransactionIDs) ?? [],
            capturedAt: userDefaults.object(forKey: Keys.purchaseTimestamp) as? Date
        )
    }

    var hasVerifiedPurchaseEvidence: Bool {
        databaseSyncSnapshot.hasVerifiedPurchaseEvidence
    }

    func markNeedsRestoreWarning() {
        userDefaults.set(true, forKey: Keys.needsRestoreWarning)
        userDefaults.synchronize()
    }

    func clearNeedsRestoreWarning() {
        userDefaults.set(false, forKey: Keys.needsRestoreWarning)
        userDefaults.synchronize()
    }

    func saveSnapshot(
        hasPurchasedForever: Bool,
        isWeatherSubscribed: Bool,
        hasGaodeEnhance: Bool,
        weatherExpireDate: Date? = nil,
        gaodeExpireDate: Date? = nil,
        productIDs: Set<String> = [],
        transactionIDs: Set<String> = [],
        originalTransactionIDs: Set<String> = []
    ) {
        userDefaults.set(hasPurchasedForever, forKey: Keys.hasPurchasedForever)
        userDefaults.set(isWeatherSubscribed, forKey: Keys.isWeatherSubscribed)
        userDefaults.set(hasGaodeEnhance, forKey: Keys.hasGaodeEnhance)

        if hasPurchasedForever || isWeatherSubscribed || hasGaodeEnhance {
            userDefaults.set(Date(), forKey: Keys.purchaseTimestamp)
            clearNeedsRestoreWarning()
        }

        if let weatherExpireDate {
            userDefaults.set(weatherExpireDate, forKey: Keys.weatherExpireDate)
        } else {
            userDefaults.removeObject(forKey: Keys.weatherExpireDate)
        }

        if let gaodeExpireDate {
            userDefaults.set(gaodeExpireDate, forKey: Keys.gaodeExpireDate)
        } else {
            userDefaults.removeObject(forKey: Keys.gaodeExpireDate)
        }

        userDefaults.set(productIDs.sorted(), forKey: Keys.productIDs)
        userDefaults.set(transactionIDs.sorted(), forKey: Keys.transactionIDs)
        userDefaults.set(originalTransactionIDs.sorted(), forKey: Keys.originalTransactionIDs)

        if !hasPurchasedForever && !isWeatherSubscribed && !hasGaodeEnhance {
            userDefaults.removeObject(forKey: Keys.purchaseTimestamp)
            clearNeedsRestoreWarning()
        }

        userDefaults.removeObject(forKey: Keys.lastDatabaseSyncDate)
        userDefaults.synchronize()
    }

    func markDatabaseSyncComplete() {
        userDefaults.set(Date(), forKey: Keys.lastDatabaseSyncDate)
        userDefaults.synchronize()
    }
}
