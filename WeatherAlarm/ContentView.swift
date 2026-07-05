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
                        Text("明日状态")
                            .font(.headline)

                        Text(settingsViewModel.tomorrowStatusText)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
