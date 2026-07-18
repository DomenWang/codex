import StoreKit
import SwiftUI

enum SubscriptionPaywallFocus: String, Identifiable {
    case general
    case weather
    case path

    var id: String { rawValue }

    var featureTitle: String? {
        switch self {
        case .general:
            return nil
        case .weather:
            return "天气功能"
        case .path:
            return "路径功能"
        }
    }

}

private enum Universal50CouponTarget {
    case weatherForever
    case pathYearly
}

@available(iOS 26.0, *)
struct PaywallView: View {
    @ObservedObject var store: StoreKitSubscriptionStore
    @ObservedObject var offerStore: PurchaseOfferStore
    let focus: SubscriptionPaywallFocus
    @StateObject private var couponStore = WeatherWakeCouponStore()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var universal50CouponTarget: Universal50CouponTarget?
    @State private var useReferral100ForForever = false
    @State private var couponErrorMessage: String?
    @State private var showExitOfferAlert = false
    @State private var didRegisterOpen = false
    @State private var didCompletePurchase = false
    @State private var didScheduleProductLoad = false
    @State private var isCrowdfundingPresented = false
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PaywallHeroView(
                        hasFriendCoupon: couponStore.availableUniversal50Coupon != nil,
                        hasReferralCoupon: couponStore.availableReferral100Coupon != nil,
                        offerStore: offerStore,
                        focus: focus,
                        canShowWeatherDiscountOffer: canShowWeatherDiscountOffer
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .opacity(hasAppeared ? 1 : 0.72)
                    .offset(y: hasAppeared ? 0 : 12)
                }

                if couponStore.availableUniversal50Coupon != nil {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            PaywallDopamineIcon(kind: .coupon, size: 30)
                            Text("你的 50 元券可解锁天气永久 248 元好友价，或路径年订阅 148 元好友价；单次购买只能使用一张券。")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(SmartWakeTheme.ink)
                        }
                    }
                }

                weatherPlansSection
                pathPlansSection

                Section {
                    Button("恢复购买") {
                        Task {
                            await store.restorePurchases()
                            await authSession.syncLocalEntitlementsIfPossible()
                            if store.hasPremiumAccess {
                                dismiss()
                            }
                        }
                    }
                }

                Section("订阅说明与条款") {
                    Text("订阅通过 Apple 账户付款并自动续期。除非在当前订阅期结束前至少 24 小时取消，否则系统会按购买页显示的价格与周期续订。你可以随时在“设置 → Apple 账户 → 订阅”中管理或取消。")
                        .font(.footnote)
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: SmartWakeReleasePolicy.privacyURL) {
                        Label("隐私政策", systemImage: "hand.raised.fill")
                    }

                    Link(destination: SmartWakeReleasePolicy.termsURL) {
                        Label("使用条款（EULA）", systemImage: "doc.text.fill")
                    }
                }

                if SmartWakeReleasePolicy.showsExperimentalFeatures {
                    Section {
                        Button {
                            isCrowdfundingPresented = true
                        } label: {
                            VStack(alignment: .leading, spacing: 13) {
                                HStack(alignment: .top, spacing: 12) {
                                    PaywallDopamineIcon(kind: .crowdfunding, size: 42)

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("新功能众筹抵扣")
                                            .font(.headline.weight(.black))
                                            .foregroundStyle(SmartWakeTheme.ink)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Text("提前支持新功能，上线后自动抵扣对应权益。")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(SmartWakeTheme.secondaryInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer(minLength: 4)

                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                }

                                Text("AI 催眠、天气外卖提醒、提前睡觉闹钟，都可以先锁定未来抵扣。")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(SmartWakeTheme.secondaryInk)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .smartWakeCrystalSurface(cornerRadius: 22, tint: .white, interactive: true)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }

                if case .failed(let message) = store.state {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(SmartWakeAmbientBackdrop(style: .premium))
            .navigationTitle("解锁安心早晨")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        if canShowWeatherDiscountOffer {
                            showExitOfferAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .alert("51% 新人优惠即将离开", isPresented: $showExitOfferAlert) {
                Button("继续看看 298 元权益", role: .cancel) {}
                Button("暂时不要", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("倒计时还在继续，回到主页也能看到。时间结束前再点进来，仍然可以按当前优惠继续购买。")
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
                if !hasAppeared {
                    if reduceMotion {
                        hasAppeared = true
                    } else {
                        withAnimation(.snappy(duration: 0.48)) {
                            hasAppeared = true
                        }
                    }
                }
                scheduleProductLoadIfNeeded(after: store.products.isEmpty ? 3.5 : 0)
                if !didRegisterOpen {
                    if !store.hasPremiumAccess {
                        offerStore.registerPaywallOpen()
                    }
                    didRegisterOpen = true
                }
            }
            .onDisappear {
                if !didCompletePurchase {
                    offerStore.syncExpiredOffer()
                }
            }
            .sheet(isPresented: $isCrowdfundingPresented) {
                NavigationStack {
                    CrowdfundingView(store: store)
                }
            }
        }
        .tint(SmartWakeTheme.teal)
    }

    private func scheduleProductLoadIfNeeded(after delay: TimeInterval) {
        guard !didScheduleProductLoad else {
            return
        }

        didScheduleProductLoad = true
        Task { @MainActor in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            store.startLoadingProductsAndEntitlements()
        }
    }

    private var canShowWeatherDiscountOffer: Bool {
        offerStore.isDiscountActive && !store.hasPremiumAccess
    }

    private var foreverPurchaseProductID: String {
        if useReferral100ForForever {
            return canShowWeatherDiscountOffer
                ? WeatherAlarmProductID.foreverWeatherReferral100
                : WeatherAlarmProductID.foreverWeatherReferral100Regular
        }

        if universal50CouponTarget == .weatherForever {
            return canShowWeatherDiscountOffer
                ? WeatherAlarmProductID.foreverWeatherFriend50
                : WeatherAlarmProductID.foreverWeatherFriend50Regular
        }

        return canShowWeatherDiscountOffer
            ? WeatherAlarmProductID.foreverCommute
            : WeatherAlarmProductID.foreverWeatherFull
    }

    private var foreverDisplayPrice: String {
        switch foreverPurchaseProductID {
        case WeatherAlarmProductID.foreverWeatherReferral100:
            return "198 元"
        case WeatherAlarmProductID.foreverWeatherReferral100Regular:
            return "498 元"
        case WeatherAlarmProductID.foreverWeatherFriend50:
            return "248 元"
        case WeatherAlarmProductID.foreverWeatherFriend50Regular:
            return "548 元"
        default:
            return canShowWeatherDiscountOffer ? "598 元 → 298 元" : "598 元"
        }
    }

    private var foreverPurchaseButtonPrice: String {
        switch foreverPurchaseProductID {
        case WeatherAlarmProductID.foreverWeatherReferral100:
            return "198 元"
        case WeatherAlarmProductID.foreverWeatherReferral100Regular:
            return "498 元"
        case WeatherAlarmProductID.foreverWeatherFriend50:
            return "248 元"
        case WeatherAlarmProductID.foreverWeatherFriend50Regular:
            return "548 元"
        default:
            return canShowWeatherDiscountOffer ? "298 元" : "598 元"
        }
    }

    private var foreverOriginalPrice: String? {
        switch foreverPurchaseProductID {
        case WeatherAlarmProductID.foreverWeatherReferral100,
             WeatherAlarmProductID.foreverWeatherFriend50:
            return "298 元"
        case WeatherAlarmProductID.foreverWeatherReferral100Regular,
             WeatherAlarmProductID.foreverWeatherFriend50Regular:
            return "598 元"
        default:
            return canShowWeatherDiscountOffer ? "598 元" : nil
        }
    }

    private var foreverPriceBadge: String? {
        switch foreverPurchaseProductID {
        case WeatherAlarmProductID.foreverWeatherReferral100,
             WeatherAlarmProductID.foreverWeatherReferral100Regular:
            return "100 元券"
        case WeatherAlarmProductID.foreverWeatherFriend50,
             WeatherAlarmProductID.foreverWeatherFriend50Regular:
            return "50 元券"
        default:
            return canShowWeatherDiscountOffer ? "限时价" : nil
        }
    }

    private var foreverCouponNote: String {
        if useReferral100ForForever {
            return canShowWeatherDiscountOffer
                ? "邀请奖励已生效：298 元减 100 元，实付 198 元"
                : "邀请奖励已生效：598 元减 100 元，实付 498 元"
        }

        if universal50CouponTarget == .weatherForever {
            return canShowWeatherDiscountOffer
                ? "好友券已生效：298 元减 50 元，实付 248 元"
                : "好友券已生效：598 元减 50 元，实付 548 元"
        }

        return canShowWeatherDiscountOffer
            ? "只含天气智能提前，不包含路径功能；本轮 298 元划线价倒计时中"
            : "只含天气智能提前，不包含路径功能；当前为 598 元原价"
    }

    private var gaodeCouponNote: String {
        return "让雨雪天的驾车、公交、骑行、步行预留更贴近真实路况"
    }

    private var pathYearlyProductID: String {
        universal50CouponTarget == .pathYearly
            ? WeatherAlarmProductID.pathYearlyFriend50
            : WeatherAlarmProductID.gaodeEnhanceYearly
    }

    private var pathYearlyFallbackPrice: String {
        pathYearlyProductID == WeatherAlarmProductID.pathYearlyFriend50 ? "148 元/年" : "198 元/年"
    }

    private var weatherPlansSection: some View {
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
                fallbackPrice: "198 元/年",
                note: "不支持 50 元代金券；直接购买更划算"
            )

            productRow(
                id: foreverPurchaseProductID,
                title: "天气永久买断",
                fallbackPrice: foreverDisplayPrice,
                note: foreverCouponNote
            )
        } header: {
            PaywallFeatureSectionHeader(
                title: "天气提前",
                subtitle: "雨雪和降温变化，交给闹钟提前准备",
                iconKind: .weatherRain
            )
        } footer: {
            Text("天气方案只包含天气智能提前，不包含路径与路况功能。")
        }
    }

    private var pathPlansSection: some View {
        Section {
            productRow(
                id: WeatherAlarmProductID.gaodeEnhance,
                title: "路径月订阅",
                fallbackPrice: "19 元/月",
                note: gaodeCouponNote
            )

            productRow(
                id: pathYearlyProductID,
                title: "路径年订阅",
                fallbackPrice: pathYearlyFallbackPrice,
                note: pathYearlyProductID == WeatherAlarmProductID.pathYearlyFriend50
                    ? "好友券已生效，全年路径提前按 148 元解锁"
                    : "堵车、换乘和雨天降速，全年自动算进闹钟"
            )
        } header: {
            PaywallFeatureSectionHeader(
                title: "路径提前",
                subtitle: "通行时间和到达要求，提前算进每个闹钟",
                iconKind: .route
            )
        } footer: {
            Text("路径方案单独解锁路线与通行时间调整；每个闹钟使用自己的路线设置。")
        }
    }

    @ViewBuilder
    private func productRow(
        id: String,
        title: String,
        fallbackPrice _: String,
        note: String
    ) -> some View {
        let product = store.product(for: id)

        if let product {
            let verifiedDisplayPrice = product.displayPrice.isEmpty ? "由 App Store 提供" : product.displayPrice
            Button {
                Task {
                    await purchase(product)
                }
            } label: {
                HStack(spacing: 12) {
                    PaywallDopamineIcon(kind: productIconKind(for: id), size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)

                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(verifiedDisplayPrice)
                            .font(.headline)

                        Text(callToActionText(for: id))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(SmartWakeTheme.tealDeep)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .smartWakeCrystalSurface(cornerRadius: 20, tint: .white, interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(store.state == .purchasing)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            couponControls(for: id)
        } else {
            Button {
                store.startLoadingProductsAndEntitlements()
            } label: {
                HStack(spacing: 12) {
                    PaywallDopamineIcon(kind: productIconKind(for: id), size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("正在连接 App Store…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("价格与周期以系统购买页显示为准")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .smartWakeCrystalSurface(cornerRadius: 20, tint: .white, interactive: true)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            couponControls(for: id)
        }
    }

    private func productIconKind(for productID: String) -> PaywallDopamineIconKind {
        switch productID {
        case WeatherAlarmProductID.weatherMonthly:
            return .weatherSun
        case WeatherAlarmProductID.weatherYearly:
            return .weatherRain
        case WeatherAlarmProductID.foreverCommute,
             WeatherAlarmProductID.foreverWeatherFull,
             WeatherAlarmProductID.foreverWeatherFriend50,
             WeatherAlarmProductID.foreverWeatherReferral100,
             WeatherAlarmProductID.foreverWeatherFriend50Regular,
             WeatherAlarmProductID.foreverWeatherReferral100Regular:
            return .forever
        case WeatherAlarmProductID.gaodeEnhance,
             WeatherAlarmProductID.gaodeEnhanceYearly,
             WeatherAlarmProductID.pathYearlyFriend50:
            return .route
        default:
            return .sparkles
        }
    }

    private func callToActionText(for productID: String) -> String {
        switch productID {
        case WeatherAlarmProductID.weatherYearly:
            return "推荐"
        case WeatherAlarmProductID.foreverCommute,
             WeatherAlarmProductID.foreverWeatherFull,
             WeatherAlarmProductID.foreverWeatherFriend50,
             WeatherAlarmProductID.foreverWeatherReferral100,
             WeatherAlarmProductID.foreverWeatherFriend50Regular,
             WeatherAlarmProductID.foreverWeatherReferral100Regular:
            return "最省心"
        case WeatherAlarmProductID.gaodeEnhanceYearly, WeatherAlarmProductID.pathYearlyFriend50:
            return "路径年卡"
        case WeatherAlarmProductID.gaodeEnhance:
            return "通勤增强"
        default:
            return "立即开启"
        }
    }

    @ViewBuilder
    private func couponControls(for productID: String) -> some View {
        if isForeverProductID(productID) {
            if couponStore.availableReferral100Coupon != nil {
                Toggle(
                    "使用 100 元永久立减券",
                    isOn: Binding(
                        get: { useReferral100ForForever },
                        set: { isSelected in
                            useReferral100ForForever = isSelected
                            if isSelected {
                                universal50CouponTarget = nil
                            }
                        }
                    )
                )
                .tint(SmartWakeTheme.teal)
            }

            if couponStore.availableUniversal50Coupon != nil {
                Toggle(
                    "使用 50 元代金券",
                    isOn: Binding(
                        get: { universal50CouponTarget == .weatherForever },
                        set: { isSelected in
                            universal50CouponTarget = isSelected ? .weatherForever : nil
                            if isSelected {
                                useReferral100ForForever = false
                            }
                        }
                    )
                )
                .tint(SmartWakeTheme.teal)
            }
        } else if (productID == WeatherAlarmProductID.gaodeEnhanceYearly
                    || productID == WeatherAlarmProductID.pathYearlyFriend50),
                  couponStore.availableUniversal50Coupon != nil {
            Toggle(
                "使用 50 元代金券",
                isOn: Binding(
                    get: { universal50CouponTarget == .pathYearly },
                    set: { isSelected in
                        universal50CouponTarget = isSelected ? .pathYearly : nil
                        if isSelected {
                            useReferral100ForForever = false
                        }
                    }
                )
            )
            .tint(SmartWakeTheme.teal)
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

        didCompletePurchase = true
        if !store.hasPremiumAccess {
            offerStore.activatePostPurchaseOffer()
        }
        await authSession.syncLocalEntitlementsIfPossible()

        if isForeverProductID(product.id),
           useReferral100ForForever {
            couponStore.markReferral100Claimed()
        }

        if selectedUniversal50ProductID == product.id {
            couponStore.markUniversal50Used()
        }

        dismiss()
    }

    private func validateCouponSelection(for productID: String) throws {
        if selectedUniversal50ProductID != nil,
           selectedUniversal50ProductID != productID {
            throw CouponEligibilityError.stackingNotAllowed
        }

        if useReferral100ForForever,
           selectedUniversal50ProductID != nil,
           selectedUniversal50ProductID.map(isForeverProductID) == true {
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

    private var selectedUniversal50ProductID: String? {
        switch universal50CouponTarget {
        case .weatherForever:
            return canShowWeatherDiscountOffer
                ? WeatherAlarmProductID.foreverWeatherFriend50
                : WeatherAlarmProductID.foreverWeatherFriend50Regular
        case .pathYearly:
            return WeatherAlarmProductID.pathYearlyFriend50
        case nil:
            return nil
        }
    }

    private func isForeverProductID(_ productID: String) -> Bool {
        productID == WeatherAlarmProductID.foreverCommute
            || productID == WeatherAlarmProductID.foreverWeatherFull
            || productID == WeatherAlarmProductID.foreverWeatherFriend50
            || productID == WeatherAlarmProductID.foreverWeatherReferral100
            || productID == WeatherAlarmProductID.foreverWeatherFriend50Regular
            || productID == WeatherAlarmProductID.foreverWeatherReferral100Regular
    }

}

@available(iOS 26.0, *)
private struct PaywallHeroView: View {
    let hasFriendCoupon: Bool
    let hasReferralCoupon: Bool
    @ObservedObject var offerStore: PurchaseOfferStore
    let focus: SubscriptionPaywallFocus
    let canShowWeatherDiscountOffer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))
                    .fixedSize(horizontal: false, vertical: true)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                PaywallBenefitMark(text: "真实天气", iconKind: .weatherRain)
                PaywallBenefitMark(
                    text: focus == .path ? "路径方案" : "天气方案",
                    iconKind: focus == .path ? .route : .sun
                )
                PaywallBenefitMark(text: "系统闹钟", iconKind: .alarm)
            }

            if hasReferralCoupon {
                PaywallCouponBanner(text: "你有 100 元永久立减券，将从当前天气买断价格中直接抵扣。")
            } else if hasFriendCoupon {
                PaywallCouponBanner(text: "好友送你的 50 元券可用于天气永久买断或路径年订阅，单次限用一张。")
            } else if canShowWeatherDiscountOffer {
                PaywallCouponBanner(text: "598 元划线价进行中，天气永久买断本轮 298 元。")
            } else {
                PaywallCouponBanner(text: "天气买断只管天气提前；路径路况需要单独开启路径订阅。")
            }
        }
        .padding(20)
        .smartWakeCrystalSurface(cornerRadius: 28, tint: .white, showsSheen: true)
        .padding(.vertical, 4)
    }

    private var headerTitle: String {
        switch focus {
        case .general:
            return "把明早的不确定，交给今晚处理"
        case .weather:
            return "天气功能"
        case .path:
            return "路径功能"
        }
    }

    private var headerSubtitle: String {
        switch focus {
        case .general:
            return "下雨、下雪、堵车、换乘变慢，都不该在你睁眼那一刻才突然出现。解锁后，智能闹钟会提前帮你算好更从容的响铃时间。"
        case .weather:
            return "选择适合的方案；实际价格、试用资格和续费条款会在购买前由系统确认。"
        case .path:
            return "选择适合的方案；实际价格、试用资格和续费条款会在购买前由系统确认。"
        }
    }

}

@available(iOS 26.0, *)
@MainActor
final class PurchaseOfferStore: ObservableObject {
    private enum WaitingReason: String {
        case none
        case dismissed
        case expired
    }

    private enum Keys {
        static let hasUsedInitialOffer = "ww_offer_v2_has_used_initial"
        static let expiresAt = "ww_offer_v2_expires_at"
        static let waitingReason = "ww_offer_v2_waiting_reason"
        static let dismissedOpenCount = "ww_offer_v2_dismissed_open_count"
        static let expiredOpenCount = "ww_offer_v2_expired_open_count"
        static let expiredTargetOpenCount = "ww_offer_v2_expired_target_open_count"
        static let reappearanceEligibleAt = "ww_offer_v3_reappearance_eligible_at"
        static let automaticReappearanceCount = "ww_offer_v3_automatic_reappearance_count"
    }

    @Published private(set) var expiresAt: Date?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.expiresAt = Self.loadDate(defaults: defaults, key: Keys.expiresAt)
        syncExpiredOffer()
    }

    var isDiscountActive: Bool {
        guard let expiresAt else {
            return false
        }

        return expiresAt > Date()
    }

    var remainingSeconds: Int {
        guard let expiresAt else {
            return 0
        }

        return max(0, Int(ceil(expiresAt.timeIntervalSinceNow)))
    }

    func registerPaywallOpen() {
        syncExpiredOffer()
        if isDiscountActive {
            return
        }

        if activateInitialOfferIfNeeded() {
            return
        }

        guard canActivateAutomaticReappearance else {
            return
        }

        switch waitingReason {
        case .dismissed:
            let nextCount = defaults.integer(forKey: Keys.dismissedOpenCount) + 1
            if nextCount >= SmartWakeEngagementPolicy.dismissedOfferOpenThreshold {
                activateDiscount(
                    duration: SmartWakeEngagementPolicy.standardOfferDuration,
                    reason: .none,
                    countsAsAutomaticReappearance: true
                )
            } else {
                defaults.set(nextCount, forKey: Keys.dismissedOpenCount)
                objectWillChange.send()
            }
        case .expired:
            let nextCount = defaults.integer(forKey: Keys.expiredOpenCount) + 1
            if nextCount >= expiredTargetOpenCount {
                activateDiscount(
                    duration: SmartWakeEngagementPolicy.standardOfferDuration,
                    reason: .none,
                    countsAsAutomaticReappearance: true
                )
            } else {
                defaults.set(nextCount, forKey: Keys.expiredOpenCount)
                objectWillChange.send()
            }
        case .none:
            break
        }
    }

    func dismissActiveOffer() {
        clearActiveOffer(waitingReason: .dismissed)
    }

    @discardableResult
    func activateInitialOfferIfNeeded() -> Bool {
        syncExpiredOffer()
        guard !isDiscountActive,
              !defaults.bool(forKey: Keys.hasUsedInitialOffer),
              waitingReason == .none else {
            return false
        }

        defaults.set(true, forKey: Keys.hasUsedInitialOffer)
        activateDiscount(duration: SmartWakeEngagementPolicy.standardOfferDuration, reason: .none)
        return true
    }

    func activatePostPurchaseOffer() {
        defaults.set(true, forKey: Keys.hasUsedInitialOffer)
        activateDiscount(duration: SmartWakeEngagementPolicy.postPurchaseOfferDuration, reason: .none)
    }

    func syncExpiredOffer() {
        guard let expiresAt else {
            return
        }

        if expiresAt <= Date() {
            clearActiveOffer(waitingReason: .expired)
        }
    }

    func refreshCountdown() {
        if isDiscountActive {
            objectWillChange.send()
        } else {
            syncExpiredOffer()
        }
    }

    private var waitingReason: WaitingReason {
        get {
            WaitingReason(rawValue: defaults.string(forKey: Keys.waitingReason) ?? "") ?? .none
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.waitingReason)
        }
    }

    private func activateDiscount(
        duration: TimeInterval,
        reason: WaitingReason,
        countsAsAutomaticReappearance: Bool = false
    ) {
        let expiryDate = Date().addingTimeInterval(duration)
        expiresAt = expiryDate
        defaults.set(expiryDate.timeIntervalSince1970, forKey: Keys.expiresAt)
        waitingReason = reason
        defaults.set(0, forKey: Keys.dismissedOpenCount)
        defaults.set(0, forKey: Keys.expiredOpenCount)
        defaults.removeObject(forKey: Keys.expiredTargetOpenCount)
        defaults.removeObject(forKey: Keys.reappearanceEligibleAt)
        if countsAsAutomaticReappearance {
            defaults.set(
                defaults.integer(forKey: Keys.automaticReappearanceCount) + 1,
                forKey: Keys.automaticReappearanceCount
            )
        }
    }

    private func clearActiveOffer(waitingReason reason: WaitingReason) {
        expiresAt = nil
        defaults.removeObject(forKey: Keys.expiresAt)
        waitingReason = reason
        defaults.set(0, forKey: Keys.dismissedOpenCount)
        defaults.set(0, forKey: Keys.expiredOpenCount)
        if reason == .expired {
            defaults.set(SmartWakeEngagementPolicy.expiredOfferOpenThreshold, forKey: Keys.expiredTargetOpenCount)
        } else {
            defaults.removeObject(forKey: Keys.expiredTargetOpenCount)
        }
        if reason != .none {
            let eligibleAt = Date().addingTimeInterval(SmartWakeEngagementPolicy.offerReappearanceCooldown)
            defaults.set(eligibleAt.timeIntervalSince1970, forKey: Keys.reappearanceEligibleAt)
        }
    }

    private var canActivateAutomaticReappearance: Bool {
        guard let eligibleAt = Self.loadDate(defaults: defaults, key: Keys.reappearanceEligibleAt) else {
            let migratedEligibilityDate = Date().addingTimeInterval(SmartWakeEngagementPolicy.offerReappearanceCooldown)
            defaults.set(migratedEligibilityDate.timeIntervalSince1970, forKey: Keys.reappearanceEligibleAt)
            return false
        }
        return SmartWakeEngagementPolicy.canShowAutomaticOfferReappearance(
            previousReappearanceCount: defaults.integer(forKey: Keys.automaticReappearanceCount),
            eligibleAt: eligibleAt,
            now: Date()
        )
    }

    private var expiredTargetOpenCount: Int {
        let target = SmartWakeEngagementPolicy.expiredOfferOpenThreshold
        if defaults.integer(forKey: Keys.expiredTargetOpenCount) != target {
            defaults.set(target, forKey: Keys.expiredTargetOpenCount)
        }
        return target
    }

    private static func loadDate(defaults: UserDefaults, key: String) -> Date? {
        let timestamp = defaults.double(forKey: key)
        guard timestamp > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }
}

private enum PaywallDopamineIconKind {
    case weatherSun
    case weatherRain
    case sun
    case route
    case alarm
    case forever
    case coupon
    case crowdfunding
    case sparkles
}

private struct PaywallBenefitMark: View {
    let text: String
    let iconKind: PaywallDopamineIconKind

    var body: some View {
        HStack(spacing: 5) {
            PaywallDopamineIcon(kind: iconKind, size: 22, showsWell: false)
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PaywallFeatureSectionHeader: View {
    let title: String
    let subtitle: String
    let iconKind: PaywallDopamineIconKind

    var body: some View {
        HStack(spacing: 10) {
            PaywallDopamineIcon(kind: iconKind, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(uiColor: .label))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .padding(.vertical, 3)
    }
}

private struct PaywallCouponBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            PaywallDopamineIcon(kind: .coupon, size: 26, showsWell: false)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SmartWakeTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.68), lineWidth: 0.8)
        }
    }
}

private struct PaywallForeverPriceLine: View {
    let currentPrice: String
    let originalPrice: String?
    let badge: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [SmartWakeTheme.sunbeam, SmartWakeTheme.sunrise],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }

            Text(currentPrice)
                .font(.headline.weight(.black))
                .foregroundStyle(originalPrice == nil ? Color.secondary : SmartWakeTheme.ink)

            if let originalPrice {
                Text(originalPrice)
                    .font(.subheadline.weight(.bold))
                    .strikethrough(true, color: .secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
}

private struct PaywallDopamineIcon: View {
    let kind: PaywallDopamineIconKind
    let size: CGFloat
    var showsWell = true

    var body: some View {
        ZStack {
            if showsWell {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(.white.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .stroke(.white.opacity(0.92), lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(0.055), radius: 4, y: 2)
            }

            glyph
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .weatherSun:
            weatherGlyph(rainy: false)
        case .weatherRain:
            weatherGlyph(rainy: true)
        case .sun:
            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.66, weight: .bold))
                .foregroundStyle(SmartWakeTheme.dopamineYellow)
                .shadow(color: SmartWakeTheme.dopamineCoral.opacity(0.20), radius: 2, y: 1)
        case .route:
            ZStack {
                Image(systemName: "map.fill")
                    .font(.system(size: size * 0.58, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(SmartWakeTheme.dopamineBlue, SmartWakeTheme.dopamineTurquoise)
                Image(systemName: "location.fill")
                    .font(.system(size: size * 0.25, weight: .black))
                    .foregroundStyle(SmartWakeTheme.dopamineCoral)
                    .offset(x: size * 0.20, y: -size * 0.19)
            }
        case .alarm:
            ZStack {
                Image(systemName: "alarm.fill")
                    .font(.system(size: size * 0.58, weight: .bold))
                    .foregroundStyle(SmartWakeTheme.dopamineViolet)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: size * 0.23, weight: .black))
                    .foregroundStyle(SmartWakeTheme.dopamineYellow)
                    .offset(x: size * 0.22, y: -size * 0.22)
            }
        case .forever:
            ZStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(SmartWakeTheme.dopamineCoral)
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.25, weight: .black))
                    .foregroundStyle(SmartWakeTheme.dopamineYellow)
                    .offset(x: size * 0.23, y: -size * 0.23)
            }
        case .coupon:
            ZStack {
                Image(systemName: "ticket.fill")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(SmartWakeTheme.dopamineYellow)
                Text("%")
                    .font(.system(size: size * 0.25, weight: .black, design: .rounded))
                    .foregroundStyle(SmartWakeTheme.dopamineCoral)
            }
        case .crowdfunding:
            ZStack {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(SmartWakeTheme.dopamineViolet)
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.32, weight: .black))
                    .foregroundStyle(SmartWakeTheme.dopamineYellow)
            }
        case .sparkles:
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.62, weight: .black))
                .symbolRenderingMode(.palette)
                .foregroundStyle(SmartWakeTheme.dopamineViolet, SmartWakeTheme.dopamineYellow)
        }
    }

    private func weatherGlyph(rainy: Bool) -> some View {
        ZStack {
            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(SmartWakeTheme.dopamineYellow)
                .offset(x: -size * 0.16, y: -size * 0.16)

            Image(systemName: "cloud.fill")
                .font(.system(size: size * 0.56, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: SmartWakeTheme.dopamineBlue.opacity(0.22), radius: 1.4, y: 1)
                .offset(x: size * 0.07, y: size * 0.04)

            if rainy {
                HStack(spacing: max(1.5, size * 0.07)) {
                    Capsule().frame(width: max(1.5, size * 0.045), height: size * 0.18)
                    Capsule().frame(width: max(1.5, size * 0.045), height: size * 0.23)
                    Capsule().frame(width: max(1.5, size * 0.045), height: size * 0.16)
                }
                .foregroundStyle(SmartWakeTheme.dopamineBlue)
                .offset(x: size * 0.08, y: size * 0.31)
            }
        }
    }
}
