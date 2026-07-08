import SwiftUI

@available(iOS 26.0, *)
struct ContentView: View {
    @EnvironmentObject private var toastCenter: ToastMessageCenter
    @EnvironmentObject private var authSession: AuthSessionViewModel
    @StateObject private var settingsViewModel = WeatherAlarmSettingsViewModel()
    @ObservedObject private var subscriptionStore: StoreKitSubscriptionStore
    @StateObject private var couponStore = WeatherWakeCouponStore()
    private let restoreWarningNotifier = PurchaseRestoreWarningNotifier()
    @State private var isPaywallPresented = false
    @State private var isInvitePresented = false
    @State private var isCrowdfundingPresented = false
    @State private var isPurchaseReminderPresented = false
    @AppStorage("ww_pending_friend_coupon") private var hasPendingFriendCoupon = false

    init(subscriptionStore: StoreKitSubscriptionStore = StoreKitSubscriptionStore()) {
        self.subscriptionStore = subscriptionStore
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WeatherMoodHeaderView(
                        baseTimeText: settingsViewModel.baseWakeUpTimeText,
                        suggestedTimeText: settingsViewModel.suggestedAlarmTimeText,
                        statusText: settingsViewModel.tomorrowStatusText,
                        weatherText: settingsViewModel.tomorrowWeatherText
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Toggle(
                        "智能天气调整",
                        isOn: Binding(
                            get: {
                                settingsViewModel.isSmartAdjustmentEnabled
                            },
                            set: { newValue in
                                handleSmartAdjustmentToggle(newValue)
                            }
                        )
                    )

                    Toggle(
                        "地图通勤智能调整",
                        isOn: Binding(
                            get: {
                                settingsViewModel.isCommuteAdjustmentEnabled
                            },
                            set: { newValue in
                                handleCommuteAdjustmentToggle(newValue)
                            }
                        )
                    )
                } footer: {
                    if subscriptionStore.hasPremiumAccess {
                        Text("天气智能调整已解锁。地图开关开启后，会把高德通勤耗时加入提前量。")
                    } else if subscriptionStore.hasGaodeEnhance {
                        Text("地图通勤智能调整已解锁。天气智能调整仍需订阅或永久买断。")
                    } else {
                        Text("未购买时无法开启。订阅后才会启用真实天气检测、地图通勤预留和系统闹钟自动调整。")
                    }
                }

                Section {
                    HStack {
                        Text("基础起床时间")
                        Spacer()
                        Text(settingsViewModel.baseWakeUpTimeText)
                            .foregroundStyle(.secondary)
                    }

                    DatePicker(
                        "设置起床时间",
                        selection: $settingsViewModel.selectedWakeUpTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: settingsViewModel.selectedWakeUpTime) {
                        settingsViewModel.saveSelectedWakeUpTime()
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("明日天气")
                            .font(.headline)

                        Text(settingsViewModel.tomorrowWeatherText)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("建议闹钟时间")
                            .font(.headline)

                        Text(settingsViewModel.suggestedAlarmTimeText)
                            .foregroundStyle(.secondary)

                        Text(settingsViewModel.tomorrowStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Stepper(
                        "下雨提前 \(settingsViewModel.rainAdvanceMinutes) 分钟",
                        value: $settingsViewModel.rainAdvanceMinutes,
                        in: 0...90,
                        step: 5
                    )
                    .onChange(of: settingsViewModel.rainAdvanceMinutes) {
                        settingsViewModel.saveWeatherAdjustmentSettings()
                    }

                    Stepper(
                        "强降水提前 \(settingsViewModel.heavyRainAdvanceMinutes) 分钟",
                        value: $settingsViewModel.heavyRainAdvanceMinutes,
                        in: settingsViewModel.rainAdvanceMinutes...120,
                        step: 5
                    )
                    .onChange(of: settingsViewModel.heavyRainAdvanceMinutes) {
                        settingsViewModel.saveWeatherAdjustmentSettings()
                    }
                } footer: {
                    Text("实际是否提前仍由 WeatherKit 的真实明日降水概率决定。")
                }

                Section {
                    Picker("通勤方式", selection: $settingsViewModel.selectedCommuteMode) {
                        ForEach(CommuteMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    if settingsViewModel.selectedCommuteMode == .transit {
                        TextField("公交城市，例如：北京", text: $settingsViewModel.commuteCity)
                            .textInputAutocapitalization(.never)
                    }

                    TextField("出发地，例如：北京市朝阳区望京SOHO", text: $settingsViewModel.commuteStartAddress)
                        .textInputAutocapitalization(.never)

                    TextField("目的地，例如：北京市海淀区中关村", text: $settingsViewModel.commuteEndAddress)
                        .textInputAutocapitalization(.never)

                    Button {
                        Task {
                            await settingsViewModel.syncCommuteRouteWithAMap()
                        }
                    } label: {
                        HStack {
                            Text("同步高德通勤路线")

                            if settingsViewModel.isSyncingCommuteRoute {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(settingsViewModel.isSyncingCommuteRoute)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前路线")
                            .font(.headline)

                        Text(settingsViewModel.commuteRouteText)
                            .foregroundStyle(.secondary)

                        if let message = settingsViewModel.commuteSyncMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(message.contains("失败") ? .red : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("路线同步会调用高德地理编码，以及驾车、公交、骑行或步行路径规划 API；雨雪会按出行方式和路线距离增加额外预留时间。API Key 未配置或网络失败时不会保存假路线。")
                }

                Section {
                    NavigationLink {
                        CrowdfundingView(store: subscriptionStore)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("新功能众筹中")
                                    .font(.headline)

                                Spacer()

                                Text("AI 98 元起")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }

                            Text("AI 催眠 98 元众筹；天气外卖提醒、提前睡觉闹钟 20 元众筹。正式上线定价时可抵扣。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("众筹权益仅用于对应服务上线后的价格抵扣，不可转让或跨服务使用。")
                }
            }
            .navigationTitle("智能闹钟")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("退出") {
                        Task {
                            await authSession.signOut()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("订阅") {
                            isPaywallPresented = true
                        }

                        Button("邀请好友") {
                            isInvitePresented = true
                        }

                        Button("功能众筹") {
                            isCrowdfundingPresented = true
                        }
                    } label: {
                        Text("更多")
                    }
                }
            }
            .sheet(isPresented: $isPaywallPresented) {
                PaywallView(store: subscriptionStore)
            }
            .sheet(isPresented: $isInvitePresented) {
                InviteView()
            }
            .sheet(isPresented: $isCrowdfundingPresented) {
                NavigationStack {
                    CrowdfundingView(store: subscriptionStore)
                }
            }
            .task {
                await subscriptionStore.loadProductsAndEntitlements()
                await restoreWarningNotifier.scheduleIfNeeded()
            }
            .onAppear {
                settingsViewModel.reload()
            }
            .alert("好友送你50元代金券", isPresented: $hasPendingFriendCoupon) {
                Button("立即领取") {
                    couponStore.grantUniversal50IfNeeded()
                    hasPendingFriendCoupon = false
                }
            } message: {
                Text("该券仅可用于天气永久买断（298元）或高德增强（5元/月），不可用于月/年订阅哦~")
            }
            .alert("先解锁安心模式", isPresented: $isPurchaseReminderPresented) {
                Button("去购买") {
                    isPaywallPresented = true
                }

                Button("先等等", role: .cancel) {}
            } message: {
                Text("智能调整需要购买后才能开启。它会在你睡着时替你看明天的雨雪、通勤和起床时间，让早晨少一点狼狈，多一点从容。")
            }
        }
        .toast(message: $toastCenter.message)
    }

    private func handleSmartAdjustmentToggle(_ isEnabled: Bool) {
        guard isEnabled else {
            do {
                try settingsViewModel.setSmartAdjustmentEnabled(false)
            } catch {
                toastCenter.showToast("设置保存失败")
            }
            return
        }

        guard subscriptionStore.hasPremiumAccess else {
            toastCenter.showToast("购买后才能开启安心模式")
            isPurchaseReminderPresented = true
            return
        }

        guard settingsViewModel.settings != nil else {
            toastCenter.showToast("请先设置基础起床时间")
            return
        }

        do {
            try settingsViewModel.setSmartAdjustmentEnabled(true)
        } catch {
            toastCenter.showToast("设置保存失败")
        }
    }

    private func handleCommuteAdjustmentToggle(_ isEnabled: Bool) {
        guard isEnabled else {
            do {
                try settingsViewModel.setCommuteAdjustmentEnabled(false)
            } catch {
                toastCenter.showToast("设置保存失败")
            }
            return
        }

        guard subscriptionStore.hasPremiumAccess || subscriptionStore.hasGaodeEnhance else {
            toastCenter.showToast("购买后才能开启安心模式")
            isPurchaseReminderPresented = true
            return
        }

        guard settingsViewModel.settings != nil else {
            toastCenter.showToast("请先设置基础起床时间")
            return
        }

        guard settingsViewModel.settings?.commuteRoute != nil else {
            toastCenter.showToast("请先保存通勤路线")
            return
        }

        do {
            try settingsViewModel.setCommuteAdjustmentEnabled(true)
        } catch {
            toastCenter.showToast("设置保存失败")
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        ContentView()
            .environmentObject(ToastMessageCenter())
            .environmentObject(AuthSessionViewModel())
    }
}

private struct WeatherMoodHeaderView: View {
    let baseTimeText: String
    let suggestedTimeText: String
    let statusText: String
    let weatherText: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.97, blue: 0.88),
                    Color(red: 0.88, green: 0.96, blue: 0.96),
                    Color(red: 0.92, green: 0.96, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RainMoodGraphic()
                .padding(.top, 16)
                .padding(.trailing, 14)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("明天早晨")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.54, green: 0.35, blue: 0.09))

                    Text("让雨天慢下来")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    MoodMetricView(title: "基础", value: baseTimeText)
                    MoodMetricView(title: "建议", value: suggestedTimeText)
                    MoodMetricView(title: "天气", value: weatherText)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("安心模式")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)

                        Text("雨和路都算进去了，明早不用临时赶时间。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))
                            .lineLimit(2)
                    }

                    Spacer()

                    Text("稳")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color(red: 0.07, green: 0.37, blue: 0.35))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Circle()
                                .stroke(Color(red: 0.07, green: 0.46, blue: 0.43).opacity(0.35), lineWidth: 2)
                        }
                }
                .padding(10)
                .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
        .padding(.vertical, 4)
    }
}

private struct MoodMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 10)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RainMoodGraphic: View {
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Capsule()
                    .fill(.white)
                    .frame(width: 76, height: 34)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

                Circle()
                    .fill(.white)
                    .frame(width: 34, height: 34)
                    .offset(x: -18, y: -8)

                Circle()
                    .fill(.white)
                    .frame(width: 42, height: 42)
                    .offset(x: 12, y: -10)
            }

            HStack(spacing: 12) {
                RainDropView(height: 18)
                RainDropView(height: 24)
                RainDropView(height: 16)
            }
            .foregroundStyle(Color(red: 0.18, green: 0.50, blue: 0.92).opacity(0.78))
        }
        .frame(width: 116, height: 118)
    }
}

private struct RainDropView: View {
    let height: CGFloat

    var body: some View {
        Capsule()
            .frame(width: 3, height: height)
    }
}
