import Foundation

/// 购买权限的本地快照。
///
/// 后台任务不应该依赖实时 StoreKit 查询，因为 Apple ID “媒体与购买”登出、
/// 网络异常或系统后台时间过短，都可能让实时校验暂时失败。购买/恢复购买成功后，
/// StoreKit 层会把 verified transaction 固化到这里；后台任务只读这个快照做决策。
final class PurchaseEntitlementSnapshotStore {
    private enum Keys {
        static let hasPurchasedForever = "ww_hasPurchasedForever"
        static let isWeatherSubscribed = "ww_isWeatherSubscribed"
        static let hasGaodeEnhance = "ww_hasGaodeEnhance"
        static let purchaseTimestamp = "ww_purchase_timestamp"
        static let weatherExpireDate = "ww_weather_expire_date"
        static let gaodeExpireDate = "ww_gaode_expire_date"
        static let needsRestoreWarning = "ww_needsRestoreWarning"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var canUseWeather: Bool {
        if userDefaults.bool(forKey: Keys.hasPurchasedForever) {
            return true
        }

        if let expireDate = userDefaults.object(forKey: Keys.weatherExpireDate) as? Date {
            return expireDate > Date()
        }

        return userDefaults.bool(forKey: Keys.isWeatherSubscribed)
    }

    var canUseGaode: Bool {
        if userDefaults.bool(forKey: Keys.hasGaodeEnhance) {
            return true
        }

        guard let expireDate = userDefaults.object(forKey: Keys.gaodeExpireDate) as? Date else {
            return false
        }

        return expireDate > Date()
    }

    var needsRestoreWarning: Bool {
        userDefaults.bool(forKey: Keys.needsRestoreWarning)
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
        gaodeExpireDate: Date? = nil
    ) {
        if hasPurchasedForever {
            userDefaults.set(true, forKey: Keys.hasPurchasedForever)
        }

        if isWeatherSubscribed {
            userDefaults.set(true, forKey: Keys.isWeatherSubscribed)
        }

        if hasGaodeEnhance {
            userDefaults.set(true, forKey: Keys.hasGaodeEnhance)
        }

        if hasPurchasedForever || isWeatherSubscribed || hasGaodeEnhance {
            userDefaults.set(Date(), forKey: Keys.purchaseTimestamp)
            clearNeedsRestoreWarning()
        }

        if let weatherExpireDate {
            userDefaults.set(weatherExpireDate, forKey: Keys.weatherExpireDate)
        }

        if let gaodeExpireDate {
            userDefaults.set(gaodeExpireDate, forKey: Keys.gaodeExpireDate)
        }

        userDefaults.synchronize()
    }
}
