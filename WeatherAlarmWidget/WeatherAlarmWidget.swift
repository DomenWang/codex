import SwiftUI
import WidgetKit

struct WeatherAlarmWidgetEntry: TimelineEntry {
    let date: Date
    let statusText: String
    let baseWakeUpTimeText: String
}

struct WeatherAlarmWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherAlarmWidgetEntry {
        WeatherAlarmWidgetEntry(
            date: Date(),
            statusText: "智能闹钟状态",
            baseWakeUpTimeText: "--:--"
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WeatherAlarmWidgetEntry) -> Void
    ) {
        completion(makeEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WeatherAlarmWidgetEntry>) -> Void
    ) {
        let entry = makeEntry()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func makeEntry() -> WeatherAlarmWidgetEntry {
        let status = WeatherAlarmStatusStore().loadLatestStatus()
        let baseText: String

        if let status {
            baseText = DateFormatter.weatherAlarmWidgetTime.string(from: status.baseWakeUpDate)
        } else {
            baseText = "--:--"
        }

        return WeatherAlarmWidgetEntry(
            date: Date(),
            statusText: status?.summaryText ?? "尚未完成明日天气检查",
            baseWakeUpTimeText: baseText
        )
    }
}

struct WeatherAlarmWidgetView: View {
    let entry: WeatherAlarmWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("智能闹钟状态")
                .font(.headline)

            Text(entry.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 4)

            HStack {
                Text("基础")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(entry.baseWakeUpTimeText)
                    .font(.title3.weight(.semibold))
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

@main
struct WeatherAlarmWidget: Widget {
    let kind = "WeatherAlarmWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WeatherAlarmWidgetProvider()
        ) { entry in
            WeatherAlarmWidgetView(entry: entry)
        }
        .configurationDisplayName("智能闹钟状态")
        .description("显示智能闹钟的基础起床时间和最近一次明日状态。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private extension DateFormatter {
    static let weatherAlarmWidgetTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
