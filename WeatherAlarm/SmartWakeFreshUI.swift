import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@available(iOS 26.0, *)
enum SmartWakeFreshEditorTarget: Identifiable {
    case wakeUp
    case ordinary(UUID)

    var id: String {
        switch self {
        case .wakeUp:
            return "wake-up"
        case .ordinary(let id):
            return "ordinary-\(id.uuidString)"
        }
    }
}

@available(iOS 26.0, *)
private enum SmartWakeSignatureTab: Hashable {
    case tomorrow
    case alarms
    case profile
}

@available(iOS 26.0, *)
enum SmartWakeTheme {
    // Spectrum Crystal keeps white as the dominant canvas while a few low-alpha
    // spectral lights give native Liquid Glass real color to refract.
    static let canvas = Color.white
    static let surface = Color.white
    static let raised = Color(red: 0.925, green: 0.968, blue: 0.982)
    // Compatibility names retained so alarm color persistence is untouched.
    // The global interaction language is the clear cyan-blue used by the
    // reference switch, with a darker companion reserved for readable text.
    static let teal = Color(red: 0.12, green: 0.75, blue: 0.88)
    static let tealDeep = Color(red: 0.04, green: 0.43, blue: 0.55)
    static let tealSoft = Color(red: 0.88, green: 0.98, blue: 1.0)
    static let sky = Color(red: 0.12, green: 0.58, blue: 0.95)
    static let skySoft = Color(red: 0.86, green: 0.95, blue: 1.0)
    static let sunrise = Color(red: 0.98, green: 0.54, blue: 0.20)
    static let sunriseSoft = Color(red: 1.0, green: 0.91, blue: 0.82)
    static let weatherMint = Color(red: 0.18, green: 0.82, blue: 0.68)
    static let weatherMintSoft = Color(red: 0.87, green: 1.0, blue: 0.96)
    static let sunbeam = Color(red: 0.96, green: 0.72, blue: 0.29)
    static let sunbeamSoft = Color(red: 1.0, green: 0.91, blue: 0.74)
    static let routeSky = Color(red: 0.12, green: 0.68, blue: 0.93)
    static let routeSkySoft = Color(red: 0.88, green: 0.97, blue: 1.0)
    static let lavender = Color(red: 0.51, green: 0.47, blue: 0.91)
    static let lavenderSoft = Color(red: 0.93, green: 0.91, blue: 1.0)
    static let dopamineBlue = Color(red: 0.12, green: 0.58, blue: 0.95)
    static let dopamineYellow = Color(red: 1.00, green: 0.83, blue: 0.23)
    static let dopamineCoral = Color(red: 1.00, green: 0.42, blue: 0.37)
    static let dopamineTurquoise = Color(red: 0.15, green: 0.78, blue: 0.78)
    static let dopamineViolet = Color(red: 0.55, green: 0.44, blue: 0.97)
    static let ink = Color(red: 0.045, green: 0.13, blue: 0.18)
    static let secondaryInk = Color(red: 0.34, green: 0.43, blue: 0.47)
    static let divider = Color.black.opacity(0.07)
    static let subtleShadow = Color(red: 0.05, green: 0.46, blue: 0.64).opacity(0.07)

    static let horizon = LinearGradient(
        colors: [skySoft, tealSoft.opacity(0.94), weatherMintSoft.opacity(0.72), canvas],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

@available(iOS 26.0, *)
enum SmartWakeBackdropStyle: Equatable {
    case morning
    case mist
    case premium
}

@available(iOS 26.0, *)
struct SmartWakeAmbientBackdrop: View {
    let style: SmartWakeBackdropStyle

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.64),
                .init(color: middleTint, location: 0.86),
                .init(color: bottomTint, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var middleTint: Color {
        switch style {
        case .morning:
            return Color(red: 0.985, green: 0.994, blue: 0.988)
        case .mist:
            return Color(red: 0.986, green: 0.994, blue: 0.989)
        case .premium:
            return Color(red: 0.985, green: 0.993, blue: 0.988)
        }
    }

    private var bottomTint: Color {
        switch style {
        case .morning:
            return Color(red: 0.963, green: 0.984, blue: 0.966)
        case .mist:
            return Color(red: 0.968, green: 0.985, blue: 0.973)
        case .premium:
            return Color(red: 0.966, green: 0.983, blue: 0.970)
        }
    }
}

@available(iOS 26.0, *)
private struct SmartWakeCrystalDepthOverlay: View {
    let cornerRadius: CGFloat
    let tint: Color
    let showsSheen: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.20),
                            SmartWakeTheme.sky.opacity(0.012),
                            tint.opacity(0.018),
                            SmartWakeTheme.weatherMint.opacity(0.012)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if showsSheen {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.18), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(-18))
                .padding(.horizontal, 34)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.88),
                            SmartWakeTheme.teal.opacity(0.14),
                            SmartWakeTheme.weatherMint.opacity(0.16),
                            tint.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.05
                )
                .padding(1)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(tint.opacity(0.075), lineWidth: 1.5)
                .blur(radius: 1.1)
                .offset(y: 1.2)
                .padding(2)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}

@available(iOS 26.0, *)
private struct SmartWakeVerticalScrollMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let motionDisabled = reduceMotion
        content.scrollTransition(.interactive, axis: .vertical) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : 0.72)
                .scaleEffect(motionDisabled || phase.isIdentity ? 1 : 0.965)
                .offset(y: motionDisabled || phase.isIdentity ? 0 : 12)
        }
    }
}

@available(iOS 26.0, *)
private struct SmartWakeHorizontalScrollMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let motionDisabled = reduceMotion
        content.scrollTransition(.interactive, axis: .horizontal) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : 0.58)
                .scaleEffect(motionDisabled || phase.isIdentity ? 1 : 0.90)
        }
    }
}

@available(iOS 26.0, *)
extension View {
    func smartWakeCrystalSurface(
        cornerRadius: CGFloat,
        tint: Color = .white,
        interactive: Bool = false,
        showsSheen: Bool = false
    ) -> some View {
        glassEffect(
            .regular
                .tint(tint.opacity(0.025))
                .interactive(interactive),
            in: .rect(cornerRadius: cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.76),
                            SmartWakeTheme.teal.opacity(0.10),
                            SmartWakeTheme.weatherMint.opacity(0.12),
                            tint.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .allowsHitTesting(false)
        }
        .overlay {
            SmartWakeCrystalDepthOverlay(
                cornerRadius: cornerRadius,
                tint: tint,
                showsSheen: showsSheen
            )
        }
        .shadow(color: SmartWakeTheme.sky.opacity(0.055), radius: 18, y: 10)
        .shadow(color: tint.opacity(0.035), radius: 7, y: 3)
    }

    func smartWakeVerticalScrollMotion() -> some View {
        modifier(SmartWakeVerticalScrollMotionModifier())
    }

    func smartWakeHorizontalScrollMotion() -> some View {
        modifier(SmartWakeHorizontalScrollMotionModifier())
    }
}

@available(iOS 26.0, *)
struct SmartWakeFreshAppShell: View {
    let wakeTimeText: String
    let wakeBaseTimeText: String
    let wakeAdvanceMinutes: Int
    let wakeWeatherAdvanceMinutes: Int
    let wakeRouteAdvanceMinutes: Int
    let alarmTitle: String
    let repeatSummary: String
    let countdownText: String
    let weatherHeadline: String
    let weatherDetail: String
    let routeDetail: String
    let hourlyForecast: [HourlyWeatherSummary]
    let wakeRoute: CommuteRoute?
    let totalAdvanceText: String?
    let ordinaryAlarms: [OrdinaryAlarmSettings]
    let ordinaryAdvanceDisplays: [UUID: AlarmAdvanceDisplay]
    let wakeThemeIndex: Int
    let wakeIconName: String
    let hasWeatherAccess: Bool
    let hasRouteAccess: Bool
    let isWakeWeatherEnabled: Bool
    let isWakeRouteEnabled: Bool
    @Binding var wakeEnabled: Bool
    let onEditWakeAlarm: () -> Void
    let onOpenWakeRoute: () -> Void
    let onEditOrdinaryAlarm: (UUID) -> Void
    let onToggleOrdinaryAlarm: (UUID, Bool) -> Void
    let onDeleteOrdinaryAlarm: (UUID) -> Void
    let onAddAlarm: () -> Void
    let onOpenPremium: () -> Void
    let onInvite: () -> Void
    let onCrowdfunding: () -> Void

    @State private var selectedTab: SmartWakeSignatureTab = .tomorrow
    @State private var selectedProfileInfo: SmartWakeProfileInfoKind?

    var body: some View {
        TabView(selection: $selectedTab) {
            tomorrowScreen
                .tag(SmartWakeSignatureTab.tomorrow)
                .tabItem {
                    Label("明早", systemImage: "sun.horizon.fill")
                }

            alarmsScreen
                .tag(SmartWakeSignatureTab.alarms)
                .tabItem {
                    Label("闹钟", systemImage: "alarm.fill")
                }

            profileScreen
                .tag(SmartWakeSignatureTab.profile)
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(SmartWakeTheme.teal)
        .tabBarMinimizeBehavior(.never)
        .onAppear(perform: applyManualInitialTabIfNeeded)
        .navigationDestination(item: $selectedProfileInfo) { kind in
            SmartWakeProfileInfoView(kind: kind)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(selectedTab == .tomorrow ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                switch selectedTab {
                case .tomorrow:
                    Menu {
                        Button("SmartWake 高级版", systemImage: "sparkles", action: onOpenPremium)
                        Button("邀请好友", systemImage: "person.2.fill", action: onInvite)
                        if SmartWakeReleasePolicy.showsExperimentalFeatures {
                            Button("新功能计划", systemImage: "lightbulb.fill", action: onCrowdfunding)
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("账户与更多")
                case .alarms:
                    Button(action: onAddAlarm) {
                        Label("新增闹钟", systemImage: "plus")
                    }
                case .profile:
                    EmptyView()
                }
            }
        }
    }

    private var tomorrowScreen: some View {
        ZStack {
            SmartWakeAmbientBackdrop(style: .morning)

            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    LazyVStack(spacing: 18) {
                        SmartWakeMorningOutcomeHero(
                            timeText: wakeTimeText,
                            baseTimeText: wakeBaseTimeText,
                            advanceMinutes: wakeAdvanceMinutes,
                            countdownText: countdownText,
                            title: alarmTitle,
                            themeIndex: wakeThemeIndex,
                            isEnabled: $wakeEnabled,
                            onEdit: onEditWakeAlarm
                        )
                        .smartWakeVerticalScrollMotion()

                        SmartWakeAdjustmentTimeline(
                            baseTimeText: wakeBaseTimeText,
                            finalTimeText: wakeTimeText,
                            advanceMinutes: wakeAdvanceMinutes,
                            weatherAdvanceMinutes: wakeWeatherAdvanceMinutes,
                            routeAdvanceMinutes: wakeRouteAdvanceMinutes,
                            weatherEnabled: hasWeatherAccess && isWakeWeatherEnabled,
                            routeEnabled: hasRouteAccess && isWakeRouteEnabled
                        )
                        .smartWakeVerticalScrollMotion()

                        SmartWakeRouteSnapshotCard(
                            route: wakeRoute,
                            routeDetail: routeDetail,
                            hasRouteAccess: hasRouteAccess,
                            isRouteEnabled: isWakeRouteEnabled,
                            onOpen: onOpenWakeRoute
                        )
                        .smartWakeVerticalScrollMotion()

                        SmartWakeSignalCluster(
                            weatherHeadline: weatherHeadline,
                            weatherDetail: weatherDetail,
                            routeDetail: routeDetail,
                            weatherAdvanceMinutes: wakeWeatherAdvanceMinutes,
                            routeAdvanceMinutes: wakeRouteAdvanceMinutes,
                            weatherEnabled: hasWeatherAccess && isWakeWeatherEnabled,
                            routeEnabled: hasRouteAccess && isWakeRouteEnabled,
                            onWeatherTap: onEditWakeAlarm,
                            onRouteTap: onOpenWakeRoute
                        )
                        .smartWakeVerticalScrollMotion()

                        if !hourlyForecast.isEmpty {
                            SmartWakeHourlyForecastCard(forecast: hourlyForecast)
                                .smartWakeVerticalScrollMotion()
                        }

                        SmartWakeDeviceReadinessCard()
                            .smartWakeVerticalScrollMotion()

                        SmartWakePlanSummaryCard(
                            title: alarmTitle,
                            repeatSummary: repeatSummary,
                            totalAdvanceText: totalAdvanceText,
                            isEnabled: wakeEnabled,
                            onEdit: onEditWakeAlarm
                        )
                        .smartWakeVerticalScrollMotion()

                        Color.clear.frame(height: 18)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var alarmsScreen: some View {
        ZStack {
            SmartWakeAmbientBackdrop(style: .mist)

            List {
                Section("唤醒方案") {
                    SmartWakePrimaryAlarmRow(
                        timeText: wakeTimeText,
                        baseTimeText: wakeBaseTimeText,
                        advanceMinutes: wakeAdvanceMinutes,
                        title: alarmTitle,
                        repeatSummary: repeatSummary,
                        totalAdvanceText: totalAdvanceText,
                        themeIndex: wakeThemeIndex,
                        iconName: wakeIconName,
                        isEnabled: $wakeEnabled,
                        onEdit: onEditWakeAlarm
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if !ordinaryAlarms.isEmpty {
                    Section("其他闹钟") {
                        ForEach(ordinaryAlarms) { alarm in
                            SmartWakeOrdinaryAlarmRow(
                                alarm: alarm,
                                advanceDisplay: ordinaryAdvanceDisplays[alarm.id],
                                hasWeatherAccess: hasWeatherAccess,
                                hasRouteAccess: hasRouteAccess,
                                onEdit: { onEditOrdinaryAlarm(alarm.id) },
                                onToggle: { onToggleOrdinaryAlarm(alarm.id, $0) },
                                onDelete: { onDeleteOrdinaryAlarm(alarm.id) }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation(.snappy(duration: 0.24)) {
                                        onDeleteOrdinaryAlarm(alarm.id)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash.fill")
                                }
                                .tint(.red)
                            }
                            .listRowInsets(EdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    Section {
                        SmartWakeEmptyAlarmState(onAdd: onAddAlarm)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                Color.clear
                    .frame(height: 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
    }

    private var profileScreen: some View {
        ZStack {
            SmartWakeAmbientBackdrop(style: .mist)

            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    LazyVStack(spacing: 16) {
                        Button(action: onOpenPremium) {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(SmartWakeTheme.teal.opacity(0.14))
                                        .frame(width: 54, height: 54)
                                    Image(systemName: "sparkles")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(SmartWakeTheme.tealDeep)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("SmartWake 高级版")
                                        .font(.headline.weight(.bold))
                                    Text("天气提前与通勤增强")
                                        .font(.subheadline)
                                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(SmartWakeTheme.ink)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .smartWakeCrystalSurface(
                                cornerRadius: 26,
                                tint: SmartWakeTheme.teal,
                                interactive: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("打开高级版订阅页面")
                        .smartWakeVerticalScrollMotion()

                        VStack(spacing: 0) {
                            Button(action: onInvite) {
                                SmartWakeSettingsRow(
                                    symbol: "person.2.fill",
                                    title: "邀请好友",
                                    tint: SmartWakeTheme.teal
                                )
                            }
                            .buttonStyle(SmartWakeProfileRowButtonStyle())
                            .accessibilityHint("打开邀请好友页面")

                            if SmartWakeReleasePolicy.showsExperimentalFeatures {
                                Divider().padding(.leading, 58)

                                Button(action: onCrowdfunding) {
                                    SmartWakeSettingsRow(symbol: "lightbulb.fill", title: "新功能计划", tint: SmartWakeTheme.sunrise)
                                }
                                .buttonStyle(SmartWakeProfileRowButtonStyle())
                                .accessibilityHint("打开新功能计划页面")
                            }
                        }
                        .smartWakeCrystalSurface(cornerRadius: 26, tint: SmartWakeTheme.teal)
                        .smartWakeVerticalScrollMotion()

                        VStack(spacing: 0) {
                            Button {
                                selectedProfileInfo = .soundOutput
                            } label: {
                                SmartWakeSettingsRow(symbol: "speaker.wave.2.fill", title: "声音输出", value: "当前设备", tint: SmartWakeTheme.sky)
                            }
                            .buttonStyle(SmartWakeProfileRowButtonStyle())

                            Divider().padding(.leading, 58)

                            Button {
                                selectedProfileInfo = .notifications
                            } label: {
                                SmartWakeSettingsRow(symbol: "bell.badge.fill", title: "通知设置", tint: SmartWakeTheme.sunrise)
                            }
                            .buttonStyle(SmartWakeProfileRowButtonStyle())

                            Divider().padding(.leading, 58)

                            Button {
                                selectedProfileInfo = .privacy
                            } label: {
                                SmartWakeSettingsRow(
                                    symbol: "hand.raised.fill",
                                    title: "隐私与数据",
                                    tint: SmartWakeTheme.dopamineViolet
                                )
                            }
                            .buttonStyle(SmartWakeProfileRowButtonStyle())
                        }
                        .smartWakeCrystalSurface(cornerRadius: 26, tint: SmartWakeTheme.sky)
                        .smartWakeVerticalScrollMotion()

                        VStack(spacing: 0) {
                            Button {
                                selectedProfileInfo = .support
                            } label: {
                                SmartWakeSettingsRow(symbol: "lifepreserver.fill", title: "开发者支持", tint: SmartWakeTheme.sky)
                            }
                            .buttonStyle(SmartWakeProfileRowButtonStyle())

                            Divider().padding(.leading, 58)

                            Button {
                                selectedProfileInfo = .declaration
                            } label: {
                                SmartWakeSettingsRow(
                                    symbol: "doc.text.fill",
                                    title: "隐私政策与使用声明",
                                    tint: SmartWakeTheme.dopamineViolet
                                )
                            }
                            .buttonStyle(SmartWakeProfileRowButtonStyle())

                            Divider().padding(.leading, 58)

                            Button {
                                selectedProfileInfo = .about
                            } label: {
                                SmartWakeSettingsRow(symbol: "info.circle.fill", title: "关于 SmartWake", value: "1.0", tint: SmartWakeTheme.sunrise)
                            }
                            .buttonStyle(SmartWakeProfileRowButtonStyle())
                        }
                        .smartWakeCrystalSurface(cornerRadius: 26, tint: SmartWakeTheme.dopamineViolet)
                        .smartWakeVerticalScrollMotion()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var navigationTitle: String {
        switch selectedTab {
        case .tomorrow: return "明早"
        case .alarms: return "闹钟"
        case .profile: return "我的"
        }
    }

    private func applyManualInitialTabIfNeeded() {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--smartwake-initial-tab=")
        }) else {
            return
        }

        switch String(argument.dropFirst("--smartwake-initial-tab=".count)) {
        case "alarms": selectedTab = .alarms
        case "profile": selectedTab = .profile
        default: selectedTab = .tomorrow
        }
    }

}

@available(iOS 26.0, *)
private struct SmartWakeMorningOutcomeHero: View {
    let timeText: String
    let baseTimeText: String
    let advanceMinutes: Int
    let countdownText: String
    let title: String
    let themeIndex: Int
    @Binding var isEnabled: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最终响铃")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(SmartWakeTheme.ink)
                }

                Spacer()

                Toggle("启用明早唤醒", isOn: $isEnabled)
                    .labelsHidden()
                    .tint(accent)
            }

            Button(action: onEdit) {
                VStack(spacing: 6) {
                    Text(timeText)
                        .font(.system(size: 72, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .foregroundStyle(SmartWakeTheme.ink)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: timeText)

                    Label(countdownText, systemImage: "hourglass.bottomhalf.filled")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartWakeTheme.tealDeep)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            HStack {
                Label(alarmTimingSummary, systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SmartWakeTheme.tealDeep)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Spacer()
                Button("编辑", action: onEdit)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(22)
        .background {
            SmartWakeAlarmThemeBackground(themeIndex: themeIndex, cornerRadius: 32)
        }
        .smartWakeCrystalSurface(
            cornerRadius: 32,
            tint: accent,
            interactive: true,
            showsSheen: true
        )
        .overlay {
            SmartWakeAlarmThemeRefraction(themeIndex: themeIndex, cornerRadius: 32)
        }
        .opacity(isEnabled ? 1 : 0.68)
        .animation(.smooth, value: isEnabled)
    }

    private var accent: Color {
        AlarmTheme.accentColor(for: themeIndex)
    }

    private var alarmTimingSummary: String {
        if advanceMinutes > 0 {
            return "\(timeText) 响铃 · 提前 \(advanceMinutes) 分钟 · 基础 \(baseTimeText)"
        }
        return "\(timeText) 响铃 · 不用提前"
    }
}

@available(iOS 26.0, *)
private struct SmartWakeAdjustmentTimeline: View {
    let baseTimeText: String
    let finalTimeText: String
    let advanceMinutes: Int
    let weatherAdvanceMinutes: Int
    let routeAdvanceMinutes: Int
    let weatherEnabled: Bool
    let routeEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("为什么是这个时间")
                    .font(.headline.weight(.bold))
                Spacer()
                Text(advanceMinutes > 0 ? "提前 \(advanceMinutes) 分钟" : "不用提前")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartWakeTheme.tealDeep)
            }

            ZStack {
                Capsule()
                    .fill(SmartWakeTheme.divider)
                    .frame(height: 3)
                    .padding(.horizontal, 18)

                HStack(alignment: .top) {
                    timelineNode(symbol: "clock.fill", title: "基础", value: baseTimeText, tint: SmartWakeTheme.secondaryInk)
                    Spacer(minLength: 0)
                    weatherTimelineNode(
                        title: "天气",
                        value: adjustmentText(
                            enabled: weatherEnabled,
                            minutes: weatherAdvanceMinutes
                        )
                    )
                    Spacer(minLength: 0)
                    timelineNode(
                        symbol: "car.fill",
                        title: "通勤",
                        value: adjustmentText(
                            enabled: routeEnabled,
                            minutes: routeAdvanceMinutes
                        ),
                        tint: SmartWakeTheme.teal
                    )
                    Spacer(minLength: 0)
                    timelineNode(symbol: "sunrise.fill", title: "响铃", value: finalTimeText, tint: SmartWakeTheme.sunrise)
                }
            }
        }
        .padding(20)
        .smartWakeCrystalSurface(cornerRadius: 26, tint: SmartWakeTheme.sunrise)
    }

    private func adjustmentText(enabled: Bool, minutes: Int) -> String {
        if !enabled {
            return "不用提前"
        }
        return minutes > 0 ? "提前\(minutes)分" : "不用提前"
    }

    private func timelineNode(symbol: String, title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(SmartWakeTheme.surface)
                    .frame(width: 34, height: 34)
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SmartWakeTheme.secondaryInk)
            Text(value)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: 62)
    }

    private func weatherTimelineNode(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(SmartWakeTheme.surface)
                    .frame(width: 34, height: 34)
                SmartWakeWeatherIcon(condition: "多云小雨", size: 18)
            }
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SmartWakeTheme.secondaryInk)
            Text(value)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: 62)
    }
}

@available(iOS 26.0, *)
private struct SmartWakeSignalCluster: View {
    let weatherHeadline: String
    let weatherDetail: String
    let routeDetail: String
    let weatherAdvanceMinutes: Int
    let routeAdvanceMinutes: Int
    let weatherEnabled: Bool
    let routeEnabled: Bool
    let onWeatherTap: () -> Void
    let onRouteTap: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                LazyHStack(spacing: 12) {
                    SmartWakeSignalGlassChip(
                        symbol: "cloud.sun.rain.fill",
                        weatherCondition: weatherHeadline,
                        title: weatherHeadline,
                        detail: "\(weatherDetail) · \(adjustmentText(enabled: weatherEnabled, minutes: weatherAdvanceMinutes))",
                        tint: SmartWakeTheme.sky,
                        isActive: weatherEnabled,
                        action: onWeatherTap
                    )
                    .frame(width: 250)
                    .smartWakeHorizontalScrollMotion()

                    SmartWakeSignalGlassChip(
                        symbol: "car.fill",
                        weatherCondition: nil,
                        title: "通勤信号",
                        detail: routeEnabled
                            ? "\(routeDetail) · \(adjustmentText(enabled: true, minutes: routeAdvanceMinutes))"
                            : "路径未启用 · 不用提前",
                        tint: SmartWakeTheme.teal,
                        isActive: routeEnabled,
                        action: onRouteTap
                    )
                    .frame(width: 250)
                    .smartWakeHorizontalScrollMotion()
                }
                .scrollTargetLayout()
            }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }

    private func adjustmentText(enabled: Bool, minutes: Int) -> String {
        if !enabled {
            return "不用提前"
        }
        return minutes > 0 ? "提前 \(minutes) 分钟" : "不用提前"
    }
}

@available(iOS 26.0, *)
private struct SmartWakeSignalGlassChip: View {
    let symbol: String
    let weatherCondition: String?
    let title: String
    let detail: String
    let tint: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
            .smartWakeCrystalSurface(cornerRadius: 20, tint: tint, interactive: true)
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                if let weatherCondition {
                    SmartWakeWeatherIcon(condition: weatherCondition, size: 20)
                } else {
                    Image(systemName: symbol)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                        .symbolEffect(.bounce, value: isActive)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(SmartWakeTheme.secondaryInk)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

@available(iOS 26.0, *)
private struct SmartWakeHourlyForecastCard: View {
    let forecast: [HourlyWeatherSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("明早逐小时")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("围绕起床时段")
                    .font(.caption)
                    .foregroundStyle(SmartWakeTheme.secondaryInk)
            }

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 10) {
                    LazyHStack(spacing: 10) {
                        ForEach(forecast) { sample in
                            VStack(spacing: 7) {
                                Text(sample.date.formatted(.dateTime.hour()))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SmartWakeTheme.secondaryInk)
                                SmartWakeWeatherIcon(
                                    condition: sample.weatherCondition,
                                    size: 22
                                )
                                Text("\(Int(sample.precipitationChancePercent.rounded()))%")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(SmartWakeTheme.ink)

                                Label(
                                    precipitationAmountText(sample.precipitationAmountMillimeters),
                                    systemImage: "drop.fill"
                                )
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(SmartWakeTheme.sky)
                                .lineLimit(1)
                            }
                            .frame(width: 70, height: 112)
                            .smartWakeCrystalSurface(cornerRadius: 17, tint: SmartWakeTheme.sky)
                            .smartWakeHorizontalScrollMotion()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .smartWakeCrystalSurface(cornerRadius: 24, tint: SmartWakeTheme.sky)
    }

    private func precipitationAmountText(_ millimeters: Double?) -> String {
        guard let millimeters, millimeters.isFinite, millimeters >= 0 else {
            return "-- 毫米"
        }
        return millimeters < 10
            ? String(format: "%.1f 毫米", millimeters)
            : String(format: "%.0f 毫米", millimeters)
    }
}

@available(iOS 26.0, *)
struct SmartWakeWeatherIcon: View {
    let condition: String
    var size: CGFloat = 24

    private enum Kind {
        case sunny
        case cloudy
        case rainy
        case foggy
        case snowy
        case stormy
    }

    var body: some View {
        ZStack {
            switch kind {
            case .sunny:
                Image(systemName: "sun.max.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SmartWakeTheme.dopamineYellow, SmartWakeTheme.sunrise],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: SmartWakeTheme.dopamineYellow.opacity(0.34), radius: 3, y: 1)

            case .cloudy:
                Image(systemName: "sun.max.fill")
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SmartWakeTheme.dopamineYellow, SmartWakeTheme.sunrise],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(x: -size * 0.24, y: -size * 0.20)
                cloud

            case .rainy:
                cloud.offset(y: -size * 0.12)
                precipitationDrops
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SmartWakeTheme.teal, SmartWakeTheme.dopamineTurquoise],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: SmartWakeTheme.tealDeep.opacity(0.24), radius: 1.5, y: 1)
                    .offset(y: size * 0.40)

            case .foggy:
                cloud.offset(y: -size * 0.18)
                VStack(spacing: size * 0.10) {
                    Capsule().frame(width: size * 0.92, height: max(1.5, size * 0.08))
                    Capsule().frame(width: size * 0.68, height: max(1.5, size * 0.08))
                }
                .foregroundStyle(
                    LinearGradient(
                        colors: [SmartWakeTheme.sky, SmartWakeTheme.dopamineTurquoise],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(y: size * 0.40)

            case .snowy:
                cloud.offset(y: -size * 0.13)
                HStack(spacing: size * 0.14) {
                    Image(systemName: "snowflake")
                    Image(systemName: "snowflake")
                }
                .font(.system(size: size * 0.30, weight: .bold))
                .foregroundStyle(SmartWakeTheme.dopamineTurquoise)
                .shadow(color: SmartWakeTheme.sky.opacity(0.22), radius: 1.5, y: 1)
                .offset(y: size * 0.42)

            case .stormy:
                cloud.offset(y: -size * 0.15)
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SmartWakeTheme.dopamineViolet, SmartWakeTheme.dopamineCoral],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: SmartWakeTheme.dopamineViolet.opacity(0.30), radius: 2, y: 1)
                    .offset(x: size * 0.05, y: size * 0.35)
                precipitationDrops
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SmartWakeTheme.teal, SmartWakeTheme.dopamineTurquoise],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(x: -size * 0.32, y: size * 0.42)
            }
        }
        .frame(width: size * 1.55, height: size * 1.42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(condition.isEmpty ? "天气" : condition)
    }

    private var cloud: some View {
        ZStack {
            Image(systemName: "cloud.fill")
                .font(.system(size: size * 1.03, weight: .semibold))
                .foregroundStyle(SmartWakeTheme.teal.opacity(0.20))
                .offset(y: size * 0.07)

            Image(systemName: "cloud.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, SmartWakeTheme.skySoft],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: SmartWakeTheme.tealDeep.opacity(0.20), radius: 2.2, y: 1.5)
        }
    }

    private var precipitationDrops: some View {
        HStack(spacing: size * 0.12) {
            Capsule().frame(width: max(2, size * 0.10), height: size * 0.34)
            Capsule().frame(width: max(2, size * 0.10), height: size * 0.42)
            Capsule().frame(width: max(2, size * 0.10), height: size * 0.31)
        }
    }

    private var kind: Kind {
        let lowercased = condition.lowercased()
        if condition.contains("雷") || lowercased.contains("thunder") || lowercased.contains("storm") {
            return .stormy
        }
        if condition.contains("雪") || lowercased.contains("snow") {
            return .snowy
        }
        if condition.contains("雨") || lowercased.contains("rain") || lowercased.contains("drizzle") {
            return .rainy
        }
        if condition.contains("雾") || lowercased.contains("fog") || lowercased.contains("haze") {
            return .foggy
        }
        if condition.contains("云") || condition.contains("阴") || lowercased.contains("cloud") || lowercased.contains("overcast") {
            return .cloudy
        }
        return .sunny
    }
}

@available(iOS 26.0, *)
private struct SmartWakeRouteSnapshotCard: View {
    let route: CommuteRoute?
    let routeDetail: String
    let hasRouteAccess: Bool
    let isRouteEnabled: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("路线地图", systemImage: "map.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(SmartWakeTheme.ink)

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: hasRouteAccess ? "slider.horizontal.3" : "lock.fill")
                        Text(hasRouteAccess ? "调整路线" : "解锁路径")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.black))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartWakeTheme.tealDeep)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .glassEffect(
                        .regular.tint(SmartWakeTheme.teal.opacity(0.05)).interactive(),
                        in: .capsule
                    )
                }

                ZStack(alignment: .bottom) {
                    if let route {
                        CommuteMapPreview(route: route, height: 230, showsStatusOverlay: false)
                    } else {
                        SmartWakeRoutePlaceholderMap(height: 230)
                    }

                    if !hasRouteAccess {
                        VStack(spacing: 5) {
                            Image(systemName: "lock.open.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(SmartWakeTheme.tealDeep)
                            Text("解锁路径智能")
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(SmartWakeTheme.ink)
                            Text("点击查看订阅方案")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SmartWakeTheme.secondaryInk)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .glassEffect(
                            .regular.tint(.white.opacity(0.10)).interactive(),
                            in: .rect(cornerRadius: 18)
                        )
                        .padding(12)
                    } else if let route {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: commuteSymbol(for: route.effectiveMode))
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(SmartWakeTheme.tealDeep)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.startName ?? "出发地")
                                    Text(route.endName ?? "目的地")
                                }
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.black))
                            }
                            .foregroundStyle(SmartWakeTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassEffect(
                                .regular.tint(.white.opacity(0.14)).interactive(),
                                in: .rect(cornerRadius: 17)
                            )
                        }
                        .padding(12)
                    } else {
                        Label("点击设置出发地与目的地", systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SmartWakeTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassEffect(
                                .regular.tint(.white.opacity(0.14)).interactive(),
                                in: .rect(cornerRadius: 17)
                            )
                            .padding(12)
                    }
                }

                HStack(spacing: 7) {
                    Circle()
                        .fill(hasRouteAccess && isRouteEnabled
                            ? SmartWakeTheme.weatherMint
                            : SmartWakeTheme.teal.opacity(0.34))
                        .frame(width: 7, height: 7)

                    Text(hasRouteAccess ? routeDetail : "解锁后按通勤路况智能调整")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartWakeTheme.tealDeep)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .smartWakeCrystalSurface(
            cornerRadius: 26,
            tint: SmartWakeTheme.teal,
            interactive: true,
            showsSheen: true
        )
        .accessibilityIdentifier("smartwake.tomorrow.route-map")
        .accessibilityLabel("路线地图")
        .accessibilityValue(hasRouteAccess ? "已开通路径功能" : "未开通路径功能")
        .accessibilityHint(hasRouteAccess ? "打开路径编辑页面" : "打开路径订阅页面")
    }

    private func commuteSymbol(for mode: CommuteMode) -> String {
        switch mode {
        case .driving: return "car.fill"
        case .transit: return "tram.fill"
        case .bicycling: return "bicycle"
        case .walking: return "figure.walk"
        }
    }
}

@available(iOS 26.0, *)
private struct SmartWakeRoutePlaceholderMap: View {
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        SmartWakeTheme.skySoft.opacity(0.82),
                        .white.opacity(0.90),
                        SmartWakeTheme.weatherMintSoft.opacity(0.76),
                        SmartWakeTheme.sunriseSoft.opacity(0.54)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.06, y: proxy.size.height * 0.72))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.94, y: proxy.size.height * 0.27),
                        control1: CGPoint(x: proxy.size.width * 0.34, y: proxy.size.height * 0.82),
                        control2: CGPoint(x: proxy.size.width * 0.60, y: proxy.size.height * 0.18)
                    )
                }
                .stroke(.white.opacity(0.88), style: StrokeStyle(lineWidth: 18, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.06, y: proxy.size.height * 0.72))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.94, y: proxy.size.height * 0.27),
                        control1: CGPoint(x: proxy.size.width * 0.34, y: proxy.size.height * 0.82),
                        control2: CGPoint(x: proxy.size.width * 0.60, y: proxy.size.height * 0.18)
                    )
                }
                .stroke(
                    SmartWakeTheme.teal.opacity(0.72),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )

                Image(systemName: "location.circle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white, SmartWakeTheme.teal)
                    .position(x: proxy.size.width * 0.12, y: proxy.size.height * 0.70)

                Image(systemName: "flag.circle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white, SmartWakeTheme.sunrise)
                    .position(x: proxy.size.width * 0.88, y: proxy.size.height * 0.29)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.vertical, 4)
    }
}

@available(iOS 26.0, *)
private struct SmartWakeDeviceReadinessCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("响铃准备", systemImage: "checkmark.shield.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SmartWakeTheme.ink)
                Spacer()
                Text("当前设备")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SmartWakeTheme.tealDeep)
            }

            SystemAlarmVolumeInfoPanel()
        }
        .padding(18)
        .smartWakeCrystalSurface(cornerRadius: 24, tint: SmartWakeTheme.teal)
    }
}

@available(iOS 26.0, *)
private struct SmartWakePlanSummaryCard: View {
    let title: String
    let repeatSummary: String
    let totalAdvanceText: String?
    let isEnabled: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(SmartWakeTheme.sunriseSoft)
                        .frame(width: 50, height: 50)
                    Image(systemName: "sunrise.fill")
                        .foregroundStyle(SmartWakeTheme.sunrise)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    Text(repeatSummary)
                        .font(.subheadline)
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                    if let totalAdvanceText {
                        Text(totalAdvanceText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SmartWakeTheme.tealDeep)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(SmartWakeTheme.ink)
            .padding(18)
            .smartWakeCrystalSurface(cornerRadius: 22, tint: SmartWakeTheme.sunrise, interactive: true)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.62)
        .animation(.smooth, value: isEnabled)
    }
}

@available(iOS 26.0, *)
private struct SmartWakeAlarmThemeRefraction: View {
    let themeIndex: Int
    let cornerRadius: CGFloat

    var body: some View {
        let colors = AlarmTheme.colors(for: themeIndex)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [colors[0].opacity(0.72), colors[1].opacity(0.48)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.6
            )
            .padding(1)
        .allowsHitTesting(false)
    }
}

@available(iOS 26.0, *)
private struct SmartWakeAlarmThemeBackground: View {
    let themeIndex: Int
    let cornerRadius: CGFloat
    var colorStrength: Double = 1

    var body: some View {
        let colors = AlarmTheme.colors(for: themeIndex)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        colors[0].opacity(0.40 * colorStrength),
                        colors[1].opacity(0.28 * colorStrength)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .allowsHitTesting(false)
    }
}

@available(iOS 26.0, *)
private struct SmartWakePrimaryAlarmRow: View {
    let timeText: String
    let baseTimeText: String
    let advanceMinutes: Int
    let title: String
    let repeatSummary: String
    let totalAdvanceText: String?
    let themeIndex: Int
    let iconName: String
    @Binding var isEnabled: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onEdit) {
                HStack(spacing: 14) {
                    Image(systemName: iconName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                        .background(accent.opacity(0.13), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(timeText)
                            .font(.system(size: 40, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text(title)
                            .font(.headline.weight(.bold))
                        Text(timingDetailText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(SmartWakeTheme.tealDeep)
                        Text(repeatSummary)
                            .font(.caption)
                            .foregroundStyle(SmartWakeTheme.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("启用", isOn: $isEnabled)
                .labelsHidden()
                .tint(accent)
        }
        .foregroundStyle(SmartWakeTheme.ink)
        .padding(18)
        .background {
            SmartWakeAlarmThemeBackground(themeIndex: themeIndex, cornerRadius: 24, colorStrength: 0.86)
        }
        .smartWakeCrystalSurface(cornerRadius: 24, tint: accent, interactive: true)
        .overlay {
            SmartWakeAlarmThemeRefraction(themeIndex: themeIndex, cornerRadius: 24)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(isEnabled ? accent : SmartWakeTheme.raised)
                .frame(width: 4)
                .padding(.vertical, 18)
        }
        .opacity(isEnabled ? 1 : 0.62)
    }

    private var accent: Color {
        AlarmTheme.accentColor(for: themeIndex)
    }

    private var timingDetailText: String {
        if advanceMinutes > 0 {
            return "实际 \(timeText) 响铃 · 提前 \(advanceMinutes) 分钟 · 基础 \(baseTimeText)"
        }
        return "实际 \(timeText) 响铃 · 不用提前"
    }
}

@available(iOS 26.0, *)
private struct SmartWakeOrdinaryAlarmRow: View {
    let alarm: OrdinaryAlarmSettings
    let advanceDisplay: AlarmAdvanceDisplay?
    let hasWeatherAccess: Bool
    let hasRouteAccess: Bool
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onEdit) {
                HStack(spacing: 14) {
                    Image(systemName: alarm.effectiveIconName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(accent)
                        .frame(width: 36, height: 36)
                        .background(accent.opacity(0.13), in: Circle())

                    Text(displayedTimeText)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                        .frame(minWidth: 68, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(alarm.effectiveTitle)
                            .font(.headline.weight(.semibold))
                        Text(alarm.repeatSummaryText)
                            .font(.caption)
                            .foregroundStyle(SmartWakeTheme.secondaryInk)
                        Text(timingDetailText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SmartWakeTheme.tealDeep)
                        if alarm.usesSmartTiming {
                            HStack(spacing: 7) {
                                if alarm.isWeatherAdjustmentEnabled && hasWeatherAccess {
                                    SmartWakeWeatherIcon(condition: "小雨", size: 15)
                                }
                                if alarm.isCommuteAdjustmentEnabled && hasRouteAccess {
                                    Image(systemName: "car.fill")
                                        .foregroundStyle(SmartWakeTheme.teal)
                                }
                            }
                            .font(.caption)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                "启用",
                isOn: Binding(get: { alarm.effectiveIsEnabled }, set: onToggle)
            )
            .labelsHidden()
            .tint(accent)

            Menu {
                Button("编辑", systemImage: "slider.horizontal.3", action: onEdit)
                Button("删除闹钟", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("更多闹钟操作")
        }
        .foregroundStyle(SmartWakeTheme.ink)
        .padding(16)
        .background {
            SmartWakeAlarmThemeBackground(
                themeIndex: alarm.effectiveThemeIndex,
                cornerRadius: 22,
                colorStrength: 0.76
            )
        }
        .smartWakeCrystalSurface(cornerRadius: 22, tint: accent, interactive: true)
        .overlay {
            SmartWakeAlarmThemeRefraction(themeIndex: alarm.effectiveThemeIndex, cornerRadius: 22)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(alarm.effectiveIsEnabled ? accent : SmartWakeTheme.raised)
                .frame(width: 4)
                .padding(.vertical, 16)
        }
        .opacity(alarm.effectiveIsEnabled ? 1 : 0.58)
        .animation(.smooth, value: alarm.effectiveIsEnabled)
    }

    private var accent: Color {
        AlarmTheme.accentColor(for: alarm.effectiveThemeIndex)
    }

    private var displayedTimeText: String {
        guard let advanceDisplay else {
            return alarm.timeText
        }
        return advanceDisplay.scheduledWakeUpDate.formatted(
            Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        )
    }

    private var timingDetailText: String {
        guard let advanceDisplay, advanceDisplay.advanceMinutes > 0 else {
            return "实际 \(alarm.timeText) 响铃 · 不用提前"
        }
        return "实际 \(displayedTimeText) 响铃 · 提前 \(advanceDisplay.advanceMinutes) 分钟 · 基础 \(alarm.timeText)"
    }
}

@available(iOS 26.0, *)
private struct SmartWakeEmptyAlarmState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "alarm.waves.left.and.right")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(SmartWakeTheme.teal)
            Text("还没有其他闹钟")
                .font(.headline.weight(.bold))
            Text("需要一个固定时间提醒时，在这里添加普通闹钟。")
                .font(.subheadline)
                .foregroundStyle(SmartWakeTheme.secondaryInk)
                .multilineTextAlignment(.center)
            Button("添加闹钟", systemImage: "plus", action: onAdd)
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .smartWakeCrystalSurface(cornerRadius: 24, tint: SmartWakeTheme.sky)
    }
}

@available(iOS 26.0, *)
struct SmartWakeFreshAlarmEditor: View {
    private enum FocusedField: Hashable {
        case alarmTitle
    }

    let screenTitle: String
    @Binding var selectedTime: Date
    @Binding var alarmTitle: String
    let themeIndex: Int
    let iconName: String
    let snoozeMinutes: Int?
    let selectedWeekdays: Set<Int>
    @Binding var soundSelection: AlarmSoundSelection
    @Binding var dismissChallenge: OrdinaryAlarmDismissChallenge
    @Binding var isLoudVolumeEnabled: Bool
    @Binding var isWeatherEnabled: Bool
    @Binding var isRouteEnabled: Bool
    @Binding var isAlarmEnabled: Bool
    @Binding var selectedArrivalTime: Date
    let weatherUnlocked: Bool
    let routeUnlocked: Bool
    let weatherSummary: String
    let routeSummary: String
    let advanceDisplay: AlarmAdvanceDisplay?
    let route: CommuteRoute?
    let selectedCommuteMode: CommuteMode
    let commuteStartText: String
    let commuteEndText: String
    let commuteRouteText: String
    let commuteSyncMessage: String?
    let isSchedulingAlarm: Bool
    let isSchedulingTestAlarm: Bool
    let onToggleWeekday: (Int) -> Void
    let onSelectWeekdays: ([Int]) -> Void
    let onAppearanceChanged: (Int, String) -> Void
    let onSnoozeChanged: ((Int) -> Void)?
    let onLockedWeather: () -> Void
    let onLockedRoute: () -> Void
    let onCommuteModeChanged: (CommuteMode) -> Void
    let onSelectCommuteStart: () -> Void
    let onSelectCommuteEnd: () -> Void
    let onScheduleTest: (() -> Void)?
    let onDelete: (() -> Void)?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isDeleteConfirmationPresented = false
    @State private var alarmTitleDraft = ""
    @State private var appearanceThemeIndex: Int?
    @State private var appearanceIconName: String?
    @State private var didInitializeDrafts = false
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                LazyVStack(spacing: 18) {
                    resultHero
                        .smartWakeVerticalScrollMotion()
                    baseTimeSection
                        .simultaneousGesture(outsideTitleTapGesture)
                    strategySection
                        .simultaneousGesture(outsideTitleTapGesture)
                    wakeMethodSection
                        .simultaneousGesture(outsideTitleTapGesture)
                    scheduleSection
                        .simultaneousGesture(outsideTitleTapGesture)
                    appearanceSection
                        .simultaneousGesture(outsideTitleTapGesture)
                    if onDelete != nil {
                        deleteSection
                            .smartWakeVerticalScrollMotion()
                            .simultaneousGesture(outsideTitleTapGesture)
                    }
                    Color.clear
                        .frame(height: 22)
                        .contentShape(Rectangle())
                        .simultaneousGesture(outsideTitleTapGesture)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(SmartWakeAmbientBackdrop(style: .morning))
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭", systemImage: "xmark") {
                    finishAlarmTitleEditing()
                    dismiss()
                }
                    .labelStyle(.iconOnly)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                finishAlarmTitleEditing()
                onAppearanceChanged(previewThemeIndex, previewIconName)
                onSave()
                dismiss()
            } label: {
                HStack(spacing: 9) {
                    if isSchedulingAlarm {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(isSchedulingAlarm ? "正在写入系统闹钟" : "保存唤醒方案")
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSchedulingAlarm)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .tint(SmartWakeTheme.teal)
        .onChange(of: focusedField) { previousField, currentField in
            if previousField == .alarmTitle, currentField != .alarmTitle {
                commitAlarmTitleDraft()
            }
        }
        .onAppear {
            guard !didInitializeDrafts else { return }
            alarmTitleDraft = alarmTitle
            appearanceThemeIndex = themeIndex
            appearanceIconName = iconName
            didInitializeDrafts = true
        }
        .onDisappear {
            commitAlarmTitleDraft()
        }
        .confirmationDialog("删除这个闹钟？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除闹钟", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后可在首页提示中撤销。")
        }
    }

    private var resultHero: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("这次要实现的结果")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                        .simultaneousGesture(outsideTitleTapGesture)
                    TextField("闹钟名称", text: $alarmTitleDraft)
                        .font(.title3.weight(.bold))
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .alarmTitle)
                        .onSubmit(finishAlarmTitleEditing)
                }

                Spacer()
                Toggle("启用闹钟", isOn: $isAlarmEnabled)
                    .labelsHidden()
                    .simultaneousGesture(outsideTitleTapGesture)
            }

            Text(effectiveRingTimeText)
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SmartWakeTheme.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: effectiveRingTimeText)
                .simultaneousGesture(outsideTitleTapGesture)

            VStack(spacing: 4) {
                if let advanceDisplay {
                    Label(
                        "实际提前 \(advanceDisplay.advanceMinutes) 分钟响铃",
                        systemImage: "hourglass"
                    )
                    .font(.subheadline.weight(.bold))
                    Text("基础时间 \(selectedTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                }
                Text(relativeRingText)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(SmartWakeTheme.tealDeep)
            .multilineTextAlignment(.center)
            .simultaneousGesture(outsideTitleTapGesture)
        }
        .padding(22)
        .background {
            SmartWakeAlarmThemeBackground(themeIndex: previewThemeIndex, cornerRadius: 30, colorStrength: 0.84)
        }
        .smartWakeCrystalSurface(
            cornerRadius: 30,
            tint: AlarmTheme.accentColor(for: previewThemeIndex),
            interactive: true,
            showsSheen: true
        )
        .overlay {
            SmartWakeAlarmThemeRefraction(themeIndex: previewThemeIndex, cornerRadius: 30)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: previewIconName)
                .font(.headline.weight(.bold))
                .foregroundStyle(AlarmTheme.accentColor(for: previewThemeIndex))
                .padding(18)
                .allowsHitTesting(false)
        }
    }

    private func finishAlarmTitleEditing() {
        commitAlarmTitleDraft()
        focusedField = nil
    }

    private func commitAlarmTitleDraft() {
        guard didInitializeDrafts, alarmTitleDraft != alarmTitle else {
            return
        }

        alarmTitle = alarmTitleDraft
    }

    private var outsideTitleTapGesture: some Gesture {
        TapGesture()
            .onEnded {
                guard focusedField == .alarmTitle else {
                    return
                }
                finishAlarmTitleEditing()
            }
    }

    private var baseTimeSection: some View {
        SmartWakeEditorSection(title: "基础时间", subtitle: "先确定你原本希望起床的时间") {
            DatePicker("基础响铃时间", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity, minHeight: 168)
        }
    }

    private var strategySection: some View {
        SmartWakeEditorSection(title: "提前策略", subtitle: "SmartWake 根据真实信号决定是否提前") {
            VStack(spacing: 0) {
                SmartWakeStrategyToggleRow(
                    symbol: "cloud.rain.fill",
                    title: "天气信号",
                    subtitle: weatherSummary,
                    isUnlocked: weatherUnlocked,
                    isOn: $isWeatherEnabled,
                    tint: SmartWakeTheme.sky,
                    onLockedTap: onLockedWeather
                )

                Divider().padding(.leading, 48)

                SmartWakeStrategyToggleRow(
                    symbol: "car.fill",
                    title: "通勤信号",
                    subtitle: routeSummary,
                    isUnlocked: routeUnlocked,
                    isOn: $isRouteEnabled,
                    tint: SmartWakeTheme.teal,
                    onLockedTap: onLockedRoute
                )

                if isRouteEnabled {
                    Divider().padding(.leading, 48)
                    commutePlanEditor
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.smooth, value: isRouteEnabled)
    }

    private var wakeMethodSection: some View {
        SmartWakeEditorSection(title: "如何叫醒我", subtitle: "铃声、音量与关闭方式") {
            VStack(spacing: 0) {
                NavigationLink {
                    SmartWakeFreshSoundPicker(selection: $soundSelection, loudVersion: isLoudVolumeEnabled)
                } label: {
                    SmartWakeSettingsRow(
                        symbol: "speaker.wave.3.fill",
                        title: "闹钟铃声",
                        value: soundSelection.displayName,
                        tint: SmartWakeTheme.sky
                    )
                }

                Divider().padding(.leading, 48)

                if let snoozeMinutes, let onSnoozeChanged {
                    Picker(
                        "稍后提醒",
                        selection: Binding(get: { snoozeMinutes }, set: onSnoozeChanged)
                    ) {
                        Text("关闭").tag(0)
                        ForEach([1, 3, 5, 7, 9, 10, 15, 20, 30], id: \.self) { minute in
                            Text("\(minute) 分钟").tag(minute)
                        }
                    }
                    .padding(16)

                    Divider().padding(.leading, 48)
                }

                Toggle(isOn: $isLoudVolumeEnabled) {
                    Label("更大音量", systemImage: "speaker.plus.fill")
                        .font(.headline)
                }
                .padding(16)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("关闭方式")
                        .font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(OrdinaryAlarmDismissChallenge.allCases) { challenge in
                            Button {
                                dismissChallenge = challenge
                            } label: {
                                Label(challenge.displayName, systemImage: missionSymbol(for: challenge))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .foregroundStyle(
                                        dismissChallenge == challenge ? SmartWakeTheme.tealDeep : SmartWakeTheme.secondaryInk
                                    )
                                    .background(
                                        dismissChallenge == challenge ? SmartWakeTheme.tealSoft : SmartWakeTheme.raised,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)

                if let onScheduleTest {
                    Divider()
                    Button(action: onScheduleTest) {
                        HStack(spacing: 12) {
                            if isSchedulingTestAlarm {
                                ProgressView()
                            } else {
                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundStyle(SmartWakeTheme.sunrise)
                            }
                            Text(isSchedulingTestAlarm ? "正在安排试响" : "1 分钟后试响")
                                .font(.headline)
                                .foregroundStyle(SmartWakeTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSchedulingTestAlarm)
                }
            }
        }
    }

    private var commutePlanEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            DatePicker(
                "到达目的地",
                selection: $selectedArrivalTime,
                displayedComponents: .hourAndMinute
            )
            .font(.headline)

            Picker(
                "通勤方式",
                selection: Binding(get: { selectedCommuteMode }, set: onCommuteModeChanged)
            ) {
                ForEach(CommuteMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            CommuteMapPreview(route: route, height: 220)

            VStack(spacing: 10) {
                SmartWakeRouteEndpointButton(
                    title: "出发地",
                    value: commuteStartText,
                    systemImage: "location.circle.fill",
                    action: onSelectCommuteStart
                )
                SmartWakeRouteEndpointButton(
                    title: "目的地",
                    value: commuteEndText,
                    systemImage: "mappin.circle.fill",
                    action: onSelectCommuteEnd
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("当前路线")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartWakeTheme.secondaryInk)
                Text(commuteRouteText)
                    .font(.subheadline)
                    .foregroundStyle(SmartWakeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let commuteSyncMessage {
                    Text(commuteSyncMessage)
                        .font(.caption)
                        .foregroundStyle(commuteSyncMessage.contains("失败") ? .red : SmartWakeTheme.secondaryInk)
                }
            }
        }
        .padding(16)
    }

    private var scheduleSection: some View {
        SmartWakeEditorSection(title: "响铃日程", subtitle: "选择每周重复日期") {
            VStack(spacing: 14) {
                HStack {
                    Text(selectedWeekdays.isEmpty ? "仅下一次" : "重复响铃")
                        .font(.headline)
                    Spacer()
                    Button {
                        onSelectWeekdays(selectedWeekdays.count == 7 ? [] : Array(1...7))
                    } label: {
                        Label("每天", systemImage: selectedWeekdays.count == 7 ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                HStack(spacing: 7) {
                    ForEach(Array(zip(1...7, ["日", "一", "二", "三", "四", "五", "六"])), id: \.0) { weekday, title in
                        Button {
                            onToggleWeekday(weekday)
                        } label: {
                            Text(title)
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(
                                    selectedWeekdays.contains(weekday) ? SmartWakeTheme.tealDeep : SmartWakeTheme.secondaryInk
                                )
                                .background(
                                    selectedWeekdays.contains(weekday) ? SmartWakeTheme.tealSoft : SmartWakeTheme.raised,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }

    private var appearanceSection: some View {
        SmartWakeEditorSection(title: "个性化", subtitle: "保留每个闹钟自己的颜色与图标") {
            SmartWakeFreshAppearancePicker(
                themeIndex: previewThemeIndex,
                iconName: previewIconName,
                onChange: { newThemeIndex, newIconName in
                    appearanceThemeIndex = newThemeIndex
                    appearanceIconName = newIconName
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            isDeleteConfirmationPresented = true
        } label: {
            Label("删除这个闹钟", systemImage: "trash")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private var relativeRingText: String {
        let calendar = Calendar.current
        let now = Date()
        if let scheduledWakeUpDate = advanceDisplay?.scheduledWakeUpDate {
            let minutes = max(0, Int(scheduledWakeUpDate.timeIntervalSince(now) / 60))
            return "约 \(minutes / 60) 小时 \(minutes % 60) 分钟后响铃"
        }
        guard let next = calendar.nextDate(
            after: now,
            matching: calendar.dateComponents([.hour, .minute], from: selectedTime),
            matchingPolicy: .nextTime
        ) else {
            return "选择下一次响铃时间"
        }
        let minutes = max(0, Int(next.timeIntervalSince(now) / 60))
        return "约 \(minutes / 60) 小时 \(minutes % 60) 分钟后响铃"
    }

    private var effectiveRingTimeText: String {
        (advanceDisplay?.scheduledWakeUpDate ?? selectedTime)
            .formatted(date: .omitted, time: .shortened)
    }

    private var previewThemeIndex: Int {
        appearanceThemeIndex ?? themeIndex
    }

    private var previewIconName: String {
        appearanceIconName ?? iconName
    }

    private func missionSymbol(for challenge: OrdinaryAlarmDismissChallenge) -> String {
        switch challenge {
        case .none: return "hand.tap.fill"
        case .shake: return "iphone.gen3.radiowaves.left.and.right"
        case .math: return "function"
        case .steps: return "figure.walk"
        }
    }
}

@available(iOS 26.0, *)
private struct SmartWakeRouteEndpointButton: View {
    let title: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(SmartWakeTheme.teal)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SmartWakeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
            .background(SmartWakeTheme.raised.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 26.0, *)
private struct SmartWakeFreshAppearancePicker: View {
    let themeIndex: Int
    let iconName: String
    let onChange: (Int, String) -> Void

    private let iconNames = [
        "alarm.fill", "sunrise.fill", "briefcase.fill", "figure.run",
        "cup.and.saucer.fill", "pills.fill", "book.fill", "fork.knife",
        "moon.stars.fill", "heart.fill"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 10) {
                    LazyHStack(spacing: 10) {
                        ForEach(AlarmTheme.rainbowOrderedThemeIndices, id: \.self) { index in
                            Button {
                                withAnimation(.snappy) {
                                    onChange(index, iconName)
                                }
                            } label: {
                                Circle()
                                    .fill(swatch(for: index))
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        if themeIndex == index {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.black))
                                                .foregroundStyle(.white)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                    .overlay {
                                        Circle()
                                            .stroke(themeIndex == index ? .white : .clear, lineWidth: 3)
                                            .padding(3)
                                    }
                            }
                            .buttonStyle(.glass)
                            .smartWakeHorizontalScrollMotion()
                            .accessibilityLabel("配色 \(index + 1)")
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 9) {
                    LazyHStack(spacing: 9) {
                        ForEach(iconNames, id: \.self) { candidate in
                            Button {
                                withAnimation(.snappy) {
                                    onChange(themeIndex, candidate)
                                }
                            } label: {
                                Image(systemName: candidate)
                                    .font(.headline)
                                    .foregroundStyle(iconName == candidate ? .white : SmartWakeTheme.tealDeep)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        iconName == candidate ? SmartWakeTheme.teal : SmartWakeTheme.tealSoft,
                                        in: Circle()
                                    )
                                    .symbolEffect(.bounce, value: iconName == candidate)
                            }
                            .buttonStyle(.glass)
                            .smartWakeHorizontalScrollMotion()
                            .accessibilityLabel("闹钟图标")
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func swatch(for index: Int) -> LinearGradient {
        return LinearGradient(
            colors: AlarmTheme.colors(for: index),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@available(iOS 26.0, *)
private struct SmartWakeEditorSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(SmartWakeTheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SmartWakeTheme.secondaryInk)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            content
        }
        .smartWakeCrystalSurface(cornerRadius: 24, tint: SmartWakeTheme.sky)
        .smartWakeVerticalScrollMotion()
    }
}

@available(iOS 26.0, *)
private struct SmartWakeStrategyToggleRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isUnlocked: Bool
    @Binding var isOn: Bool
    let tint: Color
    let onLockedTap: () -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { isUnlocked && isOn },
                set: { value in
                    if isUnlocked {
                        isOn = value
                    } else {
                        onLockedTap()
                    }
                }
            )
        ) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                        if !isUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                        .lineLimit(2)
                }
            }
        }
        .tint(tint)
        .padding(16)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityHint(isUnlocked ? "轻点切换\(title)" : "需要订阅后使用")
        .accessibilityIdentifier("smartwake.strategy.\(title == "通勤信号" ? "route" : "weather")")
    }
}

@available(iOS 26.0, *)
private enum SmartWakeProfileInfoKind: String, Identifiable, Hashable {
    case soundOutput
    case notifications
    case privacy
    case support
    case declaration
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soundOutput: return "声音输出"
        case .notifications: return "通知设置"
        case .privacy: return "隐私与数据"
        case .support: return "开发者支持"
        case .declaration: return "政策与声明"
        case .about: return "关于 SmartWake"
        }
    }

    var symbol: String {
        switch self {
        case .soundOutput: return "speaker.wave.3.fill"
        case .notifications: return "bell.badge.fill"
        case .privacy: return "hand.raised.fill"
        case .support: return "lifepreserver.fill"
        case .declaration: return "doc.text.fill"
        case .about: return "sun.horizon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .soundOutput, .support: return SmartWakeTheme.sky
        case .notifications, .about: return SmartWakeTheme.sunrise
        case .privacy, .declaration: return SmartWakeTheme.dopamineViolet
        }
    }
}

@available(iOS 26.0, *)
private struct SmartWakeProfileInfoView: View {
    let kind: SmartWakeProfileInfoKind

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            SmartWakeAmbientBackdrop(style: .mist)

            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(kind.tint)
                            .frame(width: 72, height: 72)
                            .background(kind.tint.opacity(0.13), in: Circle())
                            .symbolEffect(.bounce, value: hasAppeared)

                        Text(heroText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(SmartWakeTheme.ink)
                            .multilineTextAlignment(.center)

                        Text(heroDetail)
                            .font(.subheadline)
                            .foregroundStyle(SmartWakeTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .smartWakeCrystalSurface(cornerRadius: 28, tint: kind.tint, showsSheen: true)

                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.snappy(duration: 0.42)) {
                    hasAppeared = true
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .soundOutput:
            SystemAlarmVolumeInfoPanel()
                .smartWakeCrystalSurface(cornerRadius: 24, tint: kind.tint)

            infoCard(
                title: "响铃前建议检查",
                bullets: [
                    "确认系统闹钟与通知权限已开启。",
                    "确认设备音量足够，并在编辑闹钟时使用“1 分钟后试响”。",
                    "连接耳机或外放设备时，声音路由由 iOS 当前设备决定。"
                ]
            )

        case .notifications:
            infoCard(
                title: "通知与闹钟权限",
                bullets: [
                    "允许通知，SmartWake 才能显示提前提醒和状态信息。",
                    "闹钟是否响铃还取决于系统闹钟授权、闹钟开关和当前音量。",
                    "修改系统权限后，返回 App 会自动重新核对状态。"
                ]
            )

            actionButton("打开系统通知设置", symbol: "gearshape.fill") {
                openSystemURL(UIApplication.openNotificationSettingsURLString)
            }

        case .privacy:
            infoCard(
                title: "我们处理的信息",
                bullets: [
                    "闹钟时间、重复日期、铃声、关闭方式和智能提前开关。",
                    "经你授权的位置与路线，用于天气查询和通行时间预计。",
                    "Apple StoreKit 返回的购买与订阅状态，以及必要的运行诊断信息。"
                ]
            )

            infoCard(
                title: "你的控制权",
                bullets: [
                    "我们不会出售个人信息。闹钟与路线配置主要保存在设备本地。",
                    "你可以删除闹钟、关闭天气或路径功能，并在系统设置中撤回通知或定位权限。",
                    "关闭权限后，对应智能功能可能不可用，基础闹钟会尽量保持可用。"
                ]
            )

            actionButton("查看完整隐私政策", symbol: "hand.raised.fill") {
                openURL(SmartWakeReleasePolicy.privacyURL)
            }

        case .support:
            infoCard(
                title: "先快速排查",
                bullets: [
                    "闹钟没响：检查系统权限、App 内开关和设备音量。",
                    "天气或路线没更新：检查网络、定位权限与对应权益。",
                    "购买未生效：进入高级版页面使用“恢复购买”。",
                    "关闭验证失败：按页面提示完成摇动、算术或走动任务。"
                ]
            )

            actionButton("联系开发者支持", symbol: "envelope.fill") {
                openSupportEmail()
            }

            actionButton("打开在线支持", symbol: "safari.fill") {
                openURL(SmartWakeReleasePolicy.supportURL)
            }

        case .declaration:
            infoCard(
                title: "隐私政策摘要",
                bullets: [
                    "政策更新与生效日期：2026 年 7 月 12 日。",
                    "仅在提供闹钟、天气、路线、购买恢复、客服与稳定性改进所需范围内处理信息。",
                    "天气、地图、订阅和系统服务可能由 Apple 等系统服务处理必要请求。"
                ]
            )

            infoCard(
                title: "使用声明",
                bullets: [
                    "SmartWake 是起床与出行规划工具，不用于医疗、应急或其他安全关键场景。",
                    "实际响铃受 iOS 权限、设备状态和音量影响；天气与路线结果也可能受网络和服务状态影响。",
                    "购买由 Apple StoreKit 处理，价格、续费与退款规则以系统购买页为准。"
                ]
            )

            actionButton("查看隐私政策", symbol: "hand.raised.fill") {
                openURL(SmartWakeReleasePolicy.privacyURL)
            }

            actionButton("查看使用条款（EULA）", symbol: "doc.text.fill") {
                openURL(SmartWakeReleasePolicy.termsURL)
            }

        case .about:
            infoCard(
                title: "SmartWake 1.0",
                bullets: [
                    "把天气变化、路线预计和到达要求整合进每个闹钟。",
                    "支持普通闹钟、天气提前、路线提前、个性铃声与关闭任务。",
                    "界面采用 iOS 26 Liquid Glass，并保留清新的晨间主题。"
                ]
            )

            actionButton("打开 App 系统设置", symbol: "gearshape.fill") {
                openSystemURL(UIApplication.openSettingsURLString)
            }
        }
    }

    private func infoCard(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)

            ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(kind.tint)
                        .padding(.top, 2)
                    Text(bullet)
                        .font(.subheadline)
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .smartWakeCrystalSurface(cornerRadius: 24, tint: kind.tint)
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.glassProminent)
        .tint(kind.tint)
    }

    private var heroText: String {
        switch kind {
        case .soundOutput: return "让每次响铃都听得见"
        case .notifications: return "保持提醒链路完整"
        case .privacy: return "你的数据由你控制"
        case .support: return "遇到问题，我们一起定位"
        case .declaration: return "透明说明功能边界"
        case .about: return "为更从容的早晨而设计"
        }
    }

    private var heroDetail: String {
        switch kind {
        case .soundOutput: return "SmartWake 使用系统闹钟与当前音频输出设备；保存前可安排一次试响。"
        case .notifications: return "通知、系统闹钟权限、音量和 App 内开关共同决定提醒是否完整送达。"
        case .privacy: return "闹钟与路线配置主要保存在设备本地，定位只在获得授权后用于智能功能。"
        case .support: return "这里保留已发布版本的常见问题与开发者支持入口。"
        case .declaration: return "以下内容与已发布的隐私政策和技术支持说明保持一致。"
        case .about: return "融合天气、路线和闹钟任务的智能唤醒工具。"
        }
    }

    private func openSystemURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        openURL(url)
    }

    private func openSupportEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "domenwang@outlook.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "SmartWake 1.0 开发者支持"),
            URLQueryItem(name: "body", value: "请描述设备型号、iOS 版本、问题发生时间和复现步骤：\n\n")
        ]
        guard let url = components.url else { return }
        openURL(url)
    }
}

@available(iOS 26.0, *)
private struct SmartWakeSettingsRow: View {
    let symbol: String
    let title: String
    var value: String? = nil
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
                .font(.headline)
                .foregroundStyle(SmartWakeTheme.ink)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(SmartWakeTheme.secondaryInk)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(Rectangle())
    }
}

@available(iOS 26.0, *)
private struct SmartWakeProfileRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                configuration.isPressed
                    ? SmartWakeTheme.teal.opacity(0.08)
                    : Color.clear
            )
    }
}

@available(iOS 26.0, *)
@MainActor
struct SmartWakeFreshSoundPicker: View {
    @Binding var selection: AlarmSoundSelection
    let loudVersion: Bool
    @StateObject private var player = SmartWakeFreshSoundPreviewPlayer()
    @Environment(\.scenePhase) private var scenePhase
    @State private var customSounds = CustomAlarmSoundStore.sounds()
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                LazyVStack(spacing: 18) {
                    SmartWakeEditorSection(
                        title: "我的音频",
                        subtitle: "从“文件”导入，转换后直接设为闹钟"
                    ) {
                        VStack(spacing: 0) {
                            importButton
                            if !customSounds.isEmpty {
                                Divider().padding(.leading, 58)
                            }
                            ForEach(customSounds) { sound in
                                customSoundRow(sound)
                                if sound.id != customSounds.last?.id {
                                    Divider().padding(.leading, 58)
                                }
                            }
                        }
                    }

                    ForEach(AlarmSoundCollection.allCases) { collection in
                        let sounds = AlarmSoundChoice.allCases.filter { $0.collection == collection }
                        SmartWakeEditorSection(
                            title: collection.rawValue,
                            subtitle: collectionSubtitle(collection)
                        ) {
                            VStack(spacing: 0) {
                                ForEach(sounds) { sound in
                                    builtInSoundRow(sound, collection: collection)
                                    if sound != sounds.last {
                                        Divider().padding(.leading, 58)
                                    }
                                }
                            }
                        }
                    }

                    Text("点击铃声立即试听；离开此页或切到后台时会自动停止。用户音频为保证系统闹钟可靠响铃，会使用前 29 秒。")
                        .font(.footnote)
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                        .smartWakeVerticalScrollMotion()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .background(SmartWakeAmbientBackdrop(style: .morning))
        .navigationTitle("铃声")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else {
                if case .failure(let error) = result {
                    importErrorMessage = error.localizedDescription
                }
                return
            }

            isImporting = true
            Task {
                do {
                    let sound = try await CustomAlarmSoundStore.importSound(from: url)
                    customSounds = CustomAlarmSoundStore.sounds()
                    selection = .custom(sound.id)
                    player.play(selection, loudVersion: loudVersion)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    importErrorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
                isImporting = false
            }
        }
        .alert(
            "无法添加音频",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "请换一个音频文件重试。")
        }
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { player.stop() }
        }
    }

    private var importButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "waveform.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SmartWakeTheme.sky)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isImporting ? "正在处理音频…" : "添加我的音频")
                        .font(.headline)
                        .foregroundStyle(SmartWakeTheme.ink)
                    Text("支持 WAV、AIFF、CAF、M4A 与 MP3")
                        .font(.caption)
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                }

                Spacer()
                if isImporting {
                    ProgressView()
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(SmartWakeTheme.sky)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
    }

    private func customSoundRow(_ sound: CustomAlarmSound) -> some View {
        Button {
            selection = .custom(sound.id)
            UISelectionFeedbackGenerator().selectionChanged()
            player.play(selection, loudVersion: loudVersion)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .foregroundStyle(SmartWakeTheme.sky)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(sound.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SmartWakeTheme.ink)
                        .lineLimit(1)
                    Text("\(sound.durationText) · 我的音频")
                        .font(.caption)
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                }

                Spacer()
                if selection == .custom(sound.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SmartWakeTheme.sky)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func builtInSoundRow(
        _ sound: AlarmSoundChoice,
        collection: AlarmSoundCollection
    ) -> some View {
        Button {
            selection = .builtIn(sound)
            UISelectionFeedbackGenerator().selectionChanged()
            player.play(selection, loudVersion: loudVersion)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: collection.symbolName)
                    .foregroundStyle(SmartWakeTheme.teal)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(sound.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SmartWakeTheme.ink)
                    Text(sound.soundDescription)
                        .font(.caption)
                        .foregroundStyle(SmartWakeTheme.secondaryInk)
                }

                Spacer()
                if selection == .builtIn(sound) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SmartWakeTheme.teal)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func collectionSubtitle(_ collection: AlarmSoundCollection) -> String {
        switch collection {
        case .fresh:
            return "柔和自然，适合平稳醒来"
        case .crystal:
            return "通透清晰，带一点水晶质感"
        case .energetic:
            return "节奏鲜明，适合深度睡眠"
        case .ambient:
            return "低频氛围，保持沉静"
        }
    }
}

@available(iOS 26.0, *)
@MainActor
private final class SmartWakeFreshSoundPreviewPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ selection: AlarmSoundSelection, loudVersion: Bool) {
        stop()
        let url: URL?
        switch selection {
        case .builtIn(let sound):
            let fileName = sound.bundledFileName(loudVolumeEnabled: loudVersion)
            url = Bundle.main.url(forResource: fileName, withExtension: nil)
                ?? Bundle.main.url(
                    forResource: fileName,
                    withExtension: nil,
                    subdirectory: sound.bundledSubdirectory
                )
        case .custom(let id):
            url = CustomAlarmSoundStore.audioURL(for: id)
        }
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player.volume = 1
        player.prepareToPlay()
        player.play()
        self.player = player

        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
