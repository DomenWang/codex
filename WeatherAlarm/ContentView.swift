import SwiftUI

@available(iOS 26.0, *)
struct ContentView: View {
    @EnvironmentObject private var toastCenter: ToastMessageCenter
    @StateObject private var settingsViewModel = WeatherAlarmSettingsViewModel()
    @StateObject private var subscriptionStore = StoreKitSubscriptionStore()
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            List {
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
                    Text("路线同步会调用高德地理编码和驾车路径规划 API；API Key 未配置或网络失败时不会保存假路线。")
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
                } footer: {
                    if subscriptionStore.hasPremiumAccess {
                        Text("已解锁。后台天气检查会根据真实 WeatherKit 数据和 AlarmKit 系统闹钟调整响铃时间。")
                    } else {
                        Text("需要订阅后才能开启智能天气调整。")
                    }
                }
            }
            .navigationTitle("天气闹钟")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("订阅") {
                        isPaywallPresented = true
                    }
                }
            }
            .sheet(isPresented: $isPaywallPresented) {
                PaywallView(store: subscriptionStore)
            }
            .task {
                await subscriptionStore.loadProductsAndEntitlements()
            }
            .onAppear {
                settingsViewModel.reload()
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

        guard settingsViewModel.settings != nil else {
            toastCenter.showToast("请先设置基础起床时间")
            return
        }

        guard subscriptionStore.hasPremiumAccess else {
            isPaywallPresented = true
            return
        }

        do {
            try settingsViewModel.setSmartAdjustmentEnabled(true)
        } catch {
            toastCenter.showToast("设置保存失败")
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        ContentView()
            .environmentObject(ToastMessageCenter())
    }
}
