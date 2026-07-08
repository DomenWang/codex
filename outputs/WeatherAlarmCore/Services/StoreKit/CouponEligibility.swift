import Combine
import Foundation

enum WeatherWakeCouponType: String, Codable, Equatable {
    case ref100Off = "REF100_OFF"
    case ref50Universal = "REF50_UNIVERSAL"
}

struct WeatherWakeCoupon: Codable, Equatable, Identifiable {
    let id: UUID
    let type: WeatherWakeCouponType
    var isUsed: Bool
    var isClaimed: Bool

    init(
        id: UUID = UUID(),
        type: WeatherWakeCouponType,
        isUsed: Bool = false,
        isClaimed: Bool = false
    ) {
        self.id = id
        self.type = type
        self.isUsed = isUsed
        self.isClaimed = isClaimed
    }
}

enum CouponEligibilityError: LocalizedError, Equatable {
    case unsupportedService
    case stackingNotAllowed
    case couponAlreadyUsed

    var errorDescription: String? {
        switch self {
        case .unsupportedService:
            return "该代金券仅可用于天气永久买断或高德增强服务哦~"
        case .stackingNotAllowed:
            return "代金券不可叠加使用，请选择一项服务抵扣~"
        case .couponAlreadyUsed:
            return "该代金券已经使用过啦~"
        }
    }
}

enum CouponEligibilityValidator {
    static func validate(
        coupon: WeatherWakeCoupon,
        productID: String,
        isAlsoApplyingUniversalCouponElsewhere: Bool = false
    ) throws {
        if coupon.isUsed || coupon.isClaimed {
            throw CouponEligibilityError.couponAlreadyUsed
        }

        if isAlsoApplyingUniversalCouponElsewhere {
            throw CouponEligibilityError.stackingNotAllowed
        }

        switch coupon.type {
        case .ref100Off:
            guard productID == WeatherAlarmProductID.foreverCommute else {
                throw CouponEligibilityError.unsupportedService
            }
        case .ref50Universal:
            guard productID == WeatherAlarmProductID.foreverCommute
                    || productID == WeatherAlarmProductID.gaodeEnhance else {
                throw CouponEligibilityError.unsupportedService
            }
        }
    }
}

final class WeatherWakeCouponStore: ObservableObject {
    @Published private(set) var myCoupons: [WeatherWakeCoupon]
    @Published private(set) var referralCoupons: [WeatherWakeCoupon]

    private let defaults: UserDefaults
    private let myCouponsKey = "ww_my_coupons"
    private let referralCouponsKey = "ww_referral_coupons"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.myCoupons = Self.loadCoupons(defaults: defaults, key: myCouponsKey)
        self.referralCoupons = Self.loadCoupons(defaults: defaults, key: referralCouponsKey)
    }

    var availableUniversal50Coupon: WeatherWakeCoupon? {
        myCoupons.first { $0.type == .ref50Universal && !$0.isUsed }
    }

    var availableReferral100Coupon: WeatherWakeCoupon? {
        referralCoupons.first { $0.type == .ref100Off && !$0.isClaimed }
    }

    func grantUniversal50IfNeeded() {
        guard !myCoupons.contains(where: { $0.type == .ref50Universal }) else {
            return
        }

        myCoupons.append(WeatherWakeCoupon(type: .ref50Universal))
        save()
    }

    func grantReferral100IfNeeded() {
        guard !referralCoupons.contains(where: { $0.type == .ref100Off }) else {
            return
        }

        referralCoupons.append(WeatherWakeCoupon(type: .ref100Off))
        save()
    }

    func markUniversal50Used() {
        guard let index = myCoupons.firstIndex(where: { $0.type == .ref50Universal && !$0.isUsed }) else {
            return
        }

        myCoupons[index].isUsed = true
        save()
    }

    func markReferral100Claimed() {
        guard let index = referralCoupons.firstIndex(where: { $0.type == .ref100Off && !$0.isClaimed }) else {
            return
        }

        referralCoupons[index].isClaimed = true
        save()
    }

    private func save() {
        Self.saveCoupons(defaults: defaults, key: myCouponsKey, coupons: myCoupons)
        Self.saveCoupons(defaults: defaults, key: referralCouponsKey, coupons: referralCoupons)
    }

    private static func loadCoupons(defaults: UserDefaults, key: String) -> [WeatherWakeCoupon] {
        guard let data = defaults.data(forKey: key),
              let coupons = try? JSONDecoder().decode([WeatherWakeCoupon].self, from: data) else {
            return []
        }

        return coupons
    }

    private static func saveCoupons(defaults: UserDefaults, key: String, coupons: [WeatherWakeCoupon]) {
        guard let data = try? JSONEncoder().encode(coupons) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
