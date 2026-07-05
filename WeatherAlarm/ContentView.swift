import SwiftUI

@available(iOS 26.0, *)
struct ContentView: View {
    @EnvironmentObject private var toastCenter: ToastMessageCenter

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Weather Alarm")
                    .font(.largeTitle.bold())

                Text("天气闹钟核心模块已接入 AlarmKit、WeatherKit、BackgroundTasks 和 TransitService。")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("请在设置页接入真实起床时间、通勤路线、位置权限和 API Key 后启用后台检查。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("WeatherAlarm")
        }
        .toast(message: $toastCenter.message)
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        ContentView()
            .environmentObject(ToastMessageCenter())
    }
}

