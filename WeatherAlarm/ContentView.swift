import MapKit
import SwiftUI

@available(iOS 26.0, *)
@MainActor
struct ContentView: View {
    @EnvironmentObject private var toastCenter: ToastMessageCenter
    @StateObject private var settingsViewModel = WeatherAlarmSettingsViewModel()
    @StateObject private var locationProvider = WeatherAlarmLocationProvider()
    @ObservedObject private var subscriptionStore: StoreKitSubscriptionStore
    @StateObject private var couponStore = WeatherWakeCouponStore()
    private let restoreWarningNotifier = PurchaseRestoreWarningNotifier()
    @State private var isPaywallPresented = false
    @State private var isInvitePresented = false
    @State private var isCrowdfundingPresented = false
    @State private var isPurchaseReminderPresented = false
    @State private var isRouteEditorPresented = false
    @State private var activeRouteLocationRole: RouteLocationRole?
    @State private var hasRequestedInitialWeather = false
    @AppStorage("ww_pending_friend_coupon") private var hasPendingFriendCoupon = false

    init(subscriptionStore: StoreKitSubscriptionStore) {
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
                        weatherText: settingsViewModel.tomorrowWeatherText,
                        isRefreshing: settingsViewModel.isRefreshingWeather
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    PremiumToggleRow(
                        title: "智能天气调整",
                        subtitle: "明早有雨雪时，自动提前系统闹钟。",
                        isUnlocked: subscriptionStore.hasPremiumAccess,
                        isOn: Binding(
                            get: { settingsViewModel.isSmartAdjustmentEnabled },
                            set: { newValue in
                                handleSmartAdjustmentToggle(newValue)
                            }
                        )
                    )

                    PremiumToggleRow(
                        title: "地图通勤智能调整",
                        subtitle: "把高德路线预估、拥堵和雨雪影响一起算进起床时间。",
                        isUnlocked: subscriptionStore.hasGaodeEnhance || subscriptionStore.hasPremiumAccess,
                        isOn: Binding(
                            get: { settingsViewModel.isCommuteAdjustmentEnabled },
                            set: { newValue in
                                handleCommuteAdjustmentToggle(newValue)
                            }
                        )
                    )
                } footer: {
                    Text(subscriptionStore.hasPremiumAccess ? "TestFlight 测试版已解锁全部付费能力，方便你先验证真实天气、路线和闹钟链路。" : "未购买时无法开启；正式版会在这里弹出订阅页。")
                }

                Section {
                    HStack {
                        Text("基础起床时间")
                        Spacer()
                        Text(settingsViewModel.baseWakeUpTimeText)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    DatePicker(
                        "设置时间",
                        selection: $settingsViewModel.selectedWakeUpTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: settingsViewModel.selectedWakeUpTime) {
                        settingsViewModel.saveSelectedWakeUpTime()
                    }
                } header: {
                    Text("起床时间")
                }

                Section {
                    ForecastInsightRow(
                        title: "明早天气",
                        value: settingsViewModel.tomorrowWeatherText,
                        footnote: settingsViewModel.weatherRefreshMessage ?? "来自 WeatherKit，不使用模拟天气。"
                    )

                    ForecastInsightRow(
                        title: "闹钟建议",
                        value: settingsViewModel.suggestedAlarmTimeText,
                        footnote: settingsViewModel.tomorrowStatusText
                    )

                    Button {
                        Task {
                            await refreshWeatherFromDevice(showToast: true)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "location.viewfinder")
                            Text(settingsViewModel.isRefreshingWeather ? "正在获取真实天气" : "授权定位并刷新天气")
                            Spacer()
                            if settingsViewModel.isRefreshingWeather {
                                ProgressView()
                            }
                        }
                        .frame(minHeight: 40)
                    }
                    .disabled(settingsViewModel.isRefreshingWeather)
                } header: {
                    Text("明日预估")
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
                } header: {
                    Text("提前规则")
                } footer: {
                    Text("是否提前仍由 WeatherKit 的真实降水概率决定；这里是你的个人缓冲规则。")
                }

                Section {
                    CommuteMapPreview(route: settingsViewModel.settings?.commuteRoute)

                    VStack(spacing: 10) {
                        RouteEndpointButton(
                            title: "出发地",
                            value: routeDisplayText(
                                currentValue: settingsViewModel.commuteStartAddress,
                                fallback: settingsViewModel.settings?.commuteRoute?.startName,
                                placeholder: "点此选择出发地"
                            ),
                            systemImage: "location.circle.fill"
                        ) {
                            activeRouteLocationRole = .start
                        }

                        RouteEndpointButton(
                            title: "目的地",
                            value: routeDisplayText(
                                currentValue: settingsViewModel.commuteEndAddress,
                                fallback: settingsViewModel.settings?.commuteRoute?.endName,
                                placeholder: "点此选择目的地"
                            ),
                            systemImage: "mappin.circle.fill"
                        ) {
                            activeRouteLocationRole = .end
                        }
                    }

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

                    Button {
                        isRouteEditorPresented = true
                    } label: {
                        Label(settingsViewModel.settings?.commuteRoute == nil ? "设置通勤路线" : "编辑通勤路线", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.borderedProminent)
                } header: {
                    Text("通勤路线")
                } footer: {
                    Text("点出发地或目的地进入路线设置；保存时会真实调用高德地理编码和路线规划 API。公交路线会从地址中自动识别所在城市。")
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

                                Text("20 元起抵扣")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }

                            Text("AI 催眠、外卖提醒、提前睡觉闹钟正在路上。支持后会记入对应服务，正式上线定价时可抵扣。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("智能闹钟")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("订阅与买断") {
                            isPaywallPresented = true
                        }

                        Button("分享与券") {
                            isInvitePresented = true
                        }

                        Button("功能众筹") {
                            isCrowdfundingPresented = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
            .sheet(isPresented: $isRouteEditorPresented) {
                RouteEditorSheet(settingsViewModel: settingsViewModel)
            }
            .fullScreenCover(item: $activeRouteLocationRole) { role in
                RouteLocationSheet(role: role, settingsViewModel: settingsViewModel)
            }
            .task {
                await subscriptionStore.loadProductsAndEntitlements()
                await restoreWarningNotifier.scheduleIfNeeded()
                await requestInitialWeatherIfNeeded()
            }
            .onAppear {
                settingsViewModel.reload()
                Task {
                    await requestInitialWeatherIfNeeded()
                }
            }
            .alert("好友送你50元代金券", isPresented: $hasPendingFriendCoupon) {
                Button("立即领取") {
                    couponStore.grantUniversal50IfNeeded()
                    hasPendingFriendCoupon = false
                }
            } message: {
                Text("该券仅可用于天气永久买断或高德增强服务，不可用于月/年订阅。")
            }
            .alert("先解锁安心模式", isPresented: $isPurchaseReminderPresented) {
                Button("去购买") {
                    isPaywallPresented = true
                }

                Button("先等等", role: .cancel) {}
            } message: {
                Text("智能调整需要购买后开启。TestFlight 版已临时解锁，正式版会在这里引导订阅。")
            }
        }
        .toast(message: $toastCenter.message)
    }

    private func requestInitialWeatherIfNeeded() async {
        guard !hasRequestedInitialWeather else {
            return
        }

        hasRequestedInitialWeather = true
        await refreshWeatherFromDevice(showToast: false)
    }

    private func refreshWeatherFromDevice(showToast: Bool) async {
        do {
            let location = try await locationProvider.requestCurrentLocation()
            let didRefresh = await settingsViewModel.refreshWeatherWithCurrentLocation(location)
            if showToast {
                toastCenter.showToast(didRefresh ? "已刷新真实天气" : "天气获取失败")
            }
        } catch WeatherAlarmLocationProviderError.authorizationDenied {
            settingsViewModel.markWeatherRefreshFailed("定位权限未开启，无法查询真实天气")
            if showToast {
                toastCenter.showToast("请在系统设置中允许定位，才能获取真实天气")
            }
        } catch {
            settingsViewModel.markWeatherRefreshFailed("定位失败，暂时无法查询真实天气")
            if showToast {
                toastCenter.showToast("定位失败，暂时无法获取真实天气")
            }
        }
    }

    private func handleSmartAdjustmentToggle(_ isEnabled: Bool) {
        Task {
            await updateSmartAdjustment(isEnabled)
        }
    }

    private func updateSmartAdjustment(_ isEnabled: Bool) async {
        guard isEnabled else {
            do {
                try settingsViewModel.setSmartAdjustmentEnabled(false)
            } catch {
                toastCenter.showToast("设置保存失败")
            }
            return
        }

        guard subscriptionStore.hasPremiumAccess else {
            toastCenter.showToast("购买后才能开启智能天气调整")
            isPurchaseReminderPresented = true
            return
        }

        guard settingsViewModel.settings != nil else {
            toastCenter.showToast("请先设置基础起床时间")
            return
        }

        do {
            try await AlarmManager().requestAuthorization()
            try settingsViewModel.setSmartAdjustmentEnabled(true)
            toastCenter.showToast("智能天气调整已开启")
        } catch {
            toastCenter.showToast("闹钟权限未开启，无法自动调整")
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
            toastCenter.showToast("购买高德增强后才能开启地图通勤调整")
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
            toastCenter.showToast("地图通勤调整已开启")
        } catch {
            toastCenter.showToast("设置保存失败")
        }
    }

    private func routeDisplayText(currentValue: String, fallback: String?, placeholder: String) -> String {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        if let fallback,
           !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback
        }

        return placeholder
    }
}

private enum RouteLocationRole: String, Identifiable {
    case start
    case end

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .start:
            return "选择出发地"
        case .end:
            return "选择目的地"
        }
    }

    var fieldTitle: String {
        switch self {
        case .start:
            return "出发地"
        case .end:
            return "目的地"
        }
    }

    var placeholder: String {
        switch self {
        case .start:
            return "输入出发地，例如：北京市朝阳区望京 SOHO"
        case .end:
            return "输入目的地，例如：北京市海淀区中关村"
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        ContentView(subscriptionStore: StoreKitSubscriptionStore())
            .environmentObject(ToastMessageCenter())
    }
}

private struct PremiumToggleRow: View {
    let title: String
    let subtitle: String
    let isUnlocked: Bool
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)

                    Text(isUnlocked ? "已解锁" : "未解锁")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isUnlocked ? .green : .orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((isUnlocked ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 6)
    }
}

private struct ForecastInsightRow: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

@available(iOS 26.0, *)
private struct RouteLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let role: RouteLocationRole
    @ObservedObject var settingsViewModel: WeatherAlarmSettingsViewModel
    @State private var draftAddress = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        TextField(role.placeholder, text: $draftAddress)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    } label: {
                        Label(role.fieldTitle, systemImage: role == .start ? "location.circle.fill" : "mappin.circle.fill")
                    }
                } footer: {
                    Text("先输入完整地址保存；下一步接入高德 iOS SDK 后，这里会替换成真正的地图点选和 POI 搜索。")
                }

                Section {
                    RoutePickerMapPlaceholder(role: role)
                }
            }
            .navigationTitle(role.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                switch role {
                case .start:
                    draftAddress = settingsViewModel.commuteStartAddress
                case .end:
                    draftAddress = settingsViewModel.commuteEndAddress
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        switch role {
                        case .start:
                            settingsViewModel.commuteStartAddress = draftAddress
                        case .end:
                            settingsViewModel.commuteEndAddress = draftAddress
                        }
                        dismiss()
                    }
                    .disabled(draftAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct RoutePickerMapPlaceholder: View {
    let role: RouteLocationRole

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.18),
                    Color.cyan.opacity(0.12),
                    Color.green.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Image(systemName: role == .start ? "location.viewfinder" : "mappin.and.ellipse")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("地图点选即将接入高德 iOS SDK")
                    .font(.headline)

                Text("当前版本先保存地址并调用高德 Web 服务解析真实坐标。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@available(iOS 26.0, *)
private struct RouteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settingsViewModel: WeatherAlarmSettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("交通方式", selection: $settingsViewModel.selectedCommuteMode) {
                        ForEach(CommuteMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("公交路线不需要单独填写城市，App 会从出发地或目的地地址里自动识别；请尽量输入完整地址，例如“北京市朝阳区望京 SOHO”。")
                }

                Section {
                    LabeledContent {
                        TextField("例如：北京市朝阳区望京 SOHO", text: $settingsViewModel.commuteStartAddress)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    } label: {
                        Label("出发地", systemImage: "location.circle.fill")
                    }

                    LabeledContent {
                        TextField("例如：北京市海淀区中关村", text: $settingsViewModel.commuteEndAddress)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    } label: {
                        Label("目的地", systemImage: "mappin.circle.fill")
                    }
                } header: {
                    Text("地点")
                } footer: {
                    Text("这里会调用高德 API 解析真实坐标，不会保存无法解析的假地址。")
                }

                if let message = settingsViewModel.commuteSyncMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(message.contains("失败") || message.contains("需要") ? .red : .secondary)
                    }
                }
            }
            .navigationTitle("设置通勤路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let didSave = await settingsViewModel.syncCommuteRouteWithAMap()
                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        if settingsViewModel.isSyncingCommuteRoute {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(settingsViewModel.isSyncingCommuteRoute)
                }
            }
        }
    }
}

private struct RouteEndpointButton: View {
    let title: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(value.contains("点此") ? .secondary : .primary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

private struct WeatherMoodHeaderView: View {
    let baseTimeText: String
    let suggestedTimeText: String
    let statusText: String
    let weatherText: String
    let isRefreshing: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.90),
                    Color(red: 0.84, green: 0.94, blue: 0.96),
                    Color(red: 0.90, green: 0.93, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RainMoodGraphic()
                .padding(.top, 18)
                .padding(.trailing, 14)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SmartWake")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.45, green: 0.34, blue: 0.14))

                    Text("明早不用慌")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.09, blue: 0.16))

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
                    Image(systemName: isRefreshing ? "cloud.sun" : "sparkles")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.08, green: 0.38, blue: 0.35))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.62), in: Circle())

                    Text(isRefreshing ? "正在读取真实天气..." : "雨、雪、路线都替你提前想一步。")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))
                        .lineLimit(2)

                    Spacer()
                }
                .padding(10)
                .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
        .shadow(color: Color(red: 0.22, green: 0.36, blue: 0.48).opacity(0.16), radius: 18, y: 10)
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
        .background(.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

private struct CommuteMapPreview: View {
    let route: CommuteRoute?

    var body: some View {
        Group {
            if let route {
                RouteMapView(route: route)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text("\(route.effectiveMode.displayName) · 高德路线坐标")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(12)
                    }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    Text("保存路线后显示地图")
                        .font(.headline)

                    Text("输入出发地和目的地后，App 会调用高德 API 获取真实坐标和路线耗时。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .padding(16)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RouteMapView: UIViewRepresentable {
    let route: CommuteRoute

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.pointOfInterestFilter = .includingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        let start = MKPointAnnotation()
        start.title = route.startName ?? "出发地"
        start.coordinate = route.startCoordinate

        let end = MKPointAnnotation()
        end.title = route.endName ?? "目的地"
        end.coordinate = route.endCoordinate

        mapView.addAnnotations([start, end])

        let coordinates = [route.startCoordinate, route.endCoordinate]
        let polyline = coordinates.withUnsafeBufferPointer { buffer in
            MKPolyline(coordinates: buffer.baseAddress!, count: buffer.count)
        }
        mapView.addOverlay(polyline)

        var mapRect = polyline.boundingMapRect
        if mapRect.isNull || mapRect.size.width == 0 || mapRect.size.height == 0 {
            let point = MKMapPoint(route.startCoordinate)
            mapRect = MKMapRect(x: point.x, y: point.y, width: 10_000, height: 10_000)
        }

        mapView.setVisibleMapRect(
            mapRect,
            edgePadding: UIEdgeInsets(top: 42, left: 42, bottom: 42, right: 42),
            animated: false
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
