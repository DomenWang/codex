import StoreKit
import SwiftUI

@available(iOS 26.0, *)
struct PaywallView: View {
    @ObservedObject var store: StoreKitSubscriptionStore
    @StateObject private var couponStore = WeatherWakeCouponStore()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedUniversal50ProductID: String?
    @State private var useReferral100ForForever = false
    @State private var couponErrorMessage: String?
    @State private var showExitOfferAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PaywallHeroView(
                        hasFriendCoupon: couponStore.availableUniversal50Coupon != nil,
                        hasReferralCoupon: couponStore.availableReferral100Coupon != nil
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if couponStore.availableUniversal50Coupon != nil {
                    Section {
                        Text("你的 50 元代金券仅可用于：智能永久买断、高德路况增强。天气月订阅和年订阅不可用券。")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(red: 0.07, green: 0.37, blue: 0.35))
                    }
                }

                Section {
                    productRow(
                        id: WeatherAlarmProductID.weatherMonthly,
                        title: "天气月订阅",
                        fallbackPrice: "19 元/月",
                        note: "不支持 50 元代金券；适合先试一个月"
                    )

                    productRow(
                        id: WeatherAlarmProductID.weatherYearly,
                        title: "天气年订阅",
                        fallbackPrice: "98 元/年",
                        note: "不支持 50 元代金券；直接购买更划算"
                    )

                    productRow(
                        id: WeatherAlarmProductID.foreverCommute,
                        title: "智能永久买断",
                        fallbackPrice: "598 元 → 298 元",
                        note: foreverCouponNote
                    )

                    productRow(
                        id: WeatherAlarmProductID.gaodeEnhance,
                        title: "高德路况增强",
                        fallbackPrice: "5 元/月",
                        note: gaodeCouponNote
                    )
                } footer: {
                    Text("购买后才能开启智能天气调整。所有闹钟调整都会继续基于真实 WeatherKit、通勤服务和 AlarmKit 系统闹钟执行，不使用 Mock 数据。")
                }

                Section {
                    Button("恢复购买") {
                        Task {
                            await store.restorePurchases()
                            if store.hasPremiumAccess {
                                dismiss()
                            }
                        }
                    }
                }

                if case .failed(let message) = store.state {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("解锁安心早晨")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showExitOfferAlert = true
                    }
                }
            }
            .alert("51% 新人优惠即将离开", isPresented: $showExitOfferAlert) {
                Button("继续看看 298 元权益", role: .cancel) {}
                Button("暂时不要", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("这张新人优惠券只为本次打开保留。现在退出，下次可能就要按 598 元原价购买。")
            }
            .alert("代金券不可用", isPresented: Binding(
                get: { couponErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        couponErrorMessage = nil
                    }
                }
            )) {
                Button("知道了", role: .cancel) {
                    couponErrorMessage = nil
                }
            } message: {
                Text(couponErrorMessage ?? "")
            }
            .task {
                await store.loadProductsAndEntitlements()
            }
            .onChange(of: store.hasPremiumAccess) { _, hasAccess in
                if hasAccess {
                    dismiss()
                }
            }
        }
    }

    private var foreverCouponNote: String {
        if couponStore.availableReferral100Coupon != nil {
            return "原价 598 元；新人 51% 优惠后 298 元，再用 100 元永久立减券后 198 元"
        }

        if couponStore.availableUniversal50Coupon != nil {
            return "原价 598 元；新人 51% 优惠后 298 元，再用 50 代金券后 248 元"
        }

        return "原价 598 元；新用户本次打开获得 298 元永久购买权"
    }

    private var gaodeCouponNote: String {
        if couponStore.availableUniversal50Coupon != nil {
            return "50 代金券可抵首月，雨天把堵车、换乘、步行变慢都算进去"
        }

        return "让雨雪天的驾车、公交、骑行、步行预留更贴近真实路况"
    }

    @ViewBuilder
    private func productRow(
        id: String,
        title: String,
        fallbackPrice: String,
        note: String
    ) -> some View {
        if let product = store.product(for: id) {
            Button {
                Task {
                    await purchase(product)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)

                        Text(product.displayName.isEmpty ? fallbackPrice : product.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(product.displayPrice)
                            .font(.headline)

                        Text(callToActionText(for: id))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .disabled(store.state == .purchasing)

            couponControls(for: id)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(fallbackPrice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView()

                    Text(callToActionText(for: id))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func callToActionText(for productID: String) -> String {
        switch productID {
        case WeatherAlarmProductID.weatherYearly:
            return "推荐"
        case WeatherAlarmProductID.foreverCommute:
            return "最省心"
        case WeatherAlarmProductID.gaodeEnhance:
            return "通勤增强"
        default:
            return "立即开启"
        }
    }

    @ViewBuilder
    private func couponControls(for productID: String) -> some View {
        if productID == WeatherAlarmProductID.foreverCommute {
            if couponStore.availableReferral100Coupon != nil {
                Toggle("使用 100 元永久立减券", isOn: $useReferral100ForForever)
            }

            if couponStore.availableUniversal50Coupon != nil {
                Toggle(
                    "使用 50 元代金券",
                    isOn: Binding(
                        get: { selectedUniversal50ProductID == productID },
                        set: { isSelected in
                            selectedUniversal50ProductID = isSelected ? productID : nil
                        }
                    )
                )
            }
        } else if productID == WeatherAlarmProductID.gaodeEnhance,
                  couponStore.availableUniversal50Coupon != nil {
            Toggle(
                "使用 50 元代金券",
                isOn: Binding(
                    get: { selectedUniversal50ProductID == productID },
                    set: { isSelected in
                        selectedUniversal50ProductID = isSelected ? productID : nil
                    }
                )
            )
        }
    }

    private func purchase(_ product: Product) async {
        do {
            try validateCouponSelection(for: product.id)
        } catch {
            couponErrorMessage = error.localizedDescription
            return
        }

        let didPurchase = await store.purchase(product)
        guard didPurchase else {
            return
        }

        if product.id == WeatherAlarmProductID.foreverCommute,
           useReferral100ForForever {
            couponStore.markReferral100Claimed()
        }

        if selectedUniversal50ProductID == product.id {
            couponStore.markUniversal50Used()
        }
    }

    private func validateCouponSelection(for productID: String) throws {
        if selectedUniversal50ProductID != nil,
           selectedUniversal50ProductID != productID {
            throw CouponEligibilityError.stackingNotAllowed
        }

        if useReferral100ForForever,
           selectedUniversal50ProductID == WeatherAlarmProductID.foreverCommute {
            throw CouponEligibilityError.stackingNotAllowed
        }

        if let universal50Coupon = couponStore.availableUniversal50Coupon,
           selectedUniversal50ProductID == productID {
            try CouponEligibilityValidator.validate(
                coupon: universal50Coupon,
                productID: productID
            )
        }

        if useReferral100ForForever,
           let referral100Coupon = couponStore.availableReferral100Coupon {
            try CouponEligibilityValidator.validate(
                coupon: referral100Coupon,
                productID: productID
            )
        }

        if selectedUniversal50ProductID == WeatherAlarmProductID.weatherMonthly
            || selectedUniversal50ProductID == WeatherAlarmProductID.weatherYearly {
            throw CouponEligibilityError.unsupportedService
        }
    }
}

@available(iOS 26.0, *)
private struct PaywallHeroView: View {
    let hasFriendCoupon: Bool
    let hasReferralCoupon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("把明早的不确定，交给今晚处理")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))
                    .fixedSize(horizontal: false, vertical: true)

                Text("下雨、下雪、堵车、换乘变慢，都不该在你睁眼那一刻才突然出现。解锁后，智能闹钟会提前帮你算好更从容的响铃时间。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                PaywallBenefitPill(text: "真实天气")
                PaywallBenefitPill(text: "通勤预留")
                PaywallBenefitPill(text: "系统闹钟")
            }

            if hasReferralCoupon {
                PaywallCouponBanner(text: "你有 100 元永久立减券，智能永久买断可低至 198 元。")
            } else if hasFriendCoupon {
                PaywallCouponBanner(text: "好友送你的 50 元代金券仅可用于智能永久买断或高德增强。")
            } else {
                PaywallCouponBanner(text: "先开启一次安心早晨：少一点赶路，多一点掌控感。")
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.97, blue: 0.88),
                    Color(red: 0.88, green: 0.96, blue: 0.96),
                    Color(red: 0.92, green: 0.96, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
        .padding(.vertical, 4)
    }
}

private struct PaywallBenefitPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(red: 0.07, green: 0.37, blue: 0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PaywallCouponBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(red: 0.42, green: 0.25, blue: 0.04))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(red: 1.0, green: 0.92, blue: 0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
