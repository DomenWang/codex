import SwiftUI
import WidgetKit

struct WeatherAlarmWidgetEntry: TimelineEntry {
    let date: Date
    let hasStatus: Bool
    let scheduledWakeUpDate: Date?
    let alarmTitle: String
    let alarmIconName: String
    let alarmThemeIndex: Int
    let dayText: String
    let scheduledWakeUpTimeText: String
    let baseWakeUpTimeText: String
    let weatherCondition: String
    let precipitationChancePercent: Int
    let advanceMinutes: Int
    let weatherAdvanceMinutes: Int
    let routeAdvanceMinutes: Int
}

struct WeatherAlarmWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherAlarmWidgetEntry {
        WeatherAlarmWidgetEntry(
            date: Date(),
            hasStatus: true,
            scheduledWakeUpDate: Date().addingTimeInterval(3_600),
            alarmTitle: "起床闹钟",
            alarmIconName: "sunrise.fill",
            alarmThemeIndex: 2,
            dayText: "明天",
            scheduledWakeUpTimeText: "06:45",
            baseWakeUpTimeText: "07:00",
            weatherCondition: "中雨",
            precipitationChancePercent: 82,
            advanceMinutes: 15,
            weatherAdvanceMinutes: 10,
            routeAdvanceMinutes: 5
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WeatherAlarmWidgetEntry) -> Void
    ) {
        completion(context.isPreview ? placeholder(in: context) : makeEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WeatherAlarmWidgetEntry>) -> Void
    ) {
        let now = Date()
        let entry = makeEntry(at: now)
        let periodicRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(1_800)
        let postAlarmRefresh = entry.scheduledWakeUpDate?.addingTimeInterval(60)
        let refreshDate = [periodicRefresh, postAlarmRefresh]
            .compactMap { $0 }
            .filter { $0 > now }
            .min() ?? periodicRefresh
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func makeEntry(at now: Date = Date()) -> WeatherAlarmWidgetEntry {
        let store = WeatherAlarmStatusStore()
        var candidates: [(status: WeatherAlarmStatus, isWakeUp: Bool)] = []
        if let status = store.loadLatestStatus()?.nextOccurrence(after: now) {
            candidates.append((status, true))
        }
        candidates.append(
            contentsOf: store.loadOrdinaryAlarmStatuses().values.compactMap { status in
                status.nextOccurrence(after: now).map { ($0, false) }
            }
        )

        guard let candidate = candidates.min(by: {
            $0.status.scheduledWakeUpDate < $1.status.scheduledWakeUpDate
        }) else {
            return WeatherAlarmWidgetEntry(
                date: now,
                hasStatus: false,
                scheduledWakeUpDate: nil,
                alarmTitle: "暂无启用闹钟",
                alarmIconName: "alarm",
                alarmThemeIndex: 0,
                dayText: "打开 SmartWake 设置",
                scheduledWakeUpTimeText: "--:--",
                baseWakeUpTimeText: "--:--",
                weatherCondition: "等待天气更新",
                precipitationChancePercent: 0,
                advanceMinutes: 0,
                weatherAdvanceMinutes: 0,
                routeAdvanceMinutes: 0
            )
        }

        let status = candidate.status
        let isWakeUp = status.isWakeUpAlarm ?? candidate.isWakeUp
        return WeatherAlarmWidgetEntry(
            date: now,
            hasStatus: true,
            scheduledWakeUpDate: status.scheduledWakeUpDate,
            alarmTitle: status.alarmTitle ?? (isWakeUp ? "起床闹钟" : "其他闹钟"),
            alarmIconName: status.alarmIconName ?? (isWakeUp ? "sunrise.fill" : "alarm.fill"),
            alarmThemeIndex: max(0, status.alarmThemeIndex ?? 0),
            dayText: dayText(for: status.scheduledWakeUpDate, relativeTo: now),
            scheduledWakeUpTimeText: DateFormatter.weatherAlarmWidgetTime.string(from: status.scheduledWakeUpDate),
            baseWakeUpTimeText: DateFormatter.weatherAlarmWidgetTime.string(from: status.baseWakeUpDate),
            weatherCondition: normalizedWeatherCondition(status.weatherCondition),
            precipitationChancePercent: Int(status.precipitationChancePercent.rounded()),
            advanceMinutes: max(0, status.advanceMinutes),
            weatherAdvanceMinutes: max(0, status.weatherBufferMinutes),
            routeAdvanceMinutes: max(0, status.commuteDelayMinutes)
        )
    }

    private func dayText(for date: Date, relativeTo now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天"
        }
        return DateFormatter.weatherAlarmWidgetDay.string(from: date)
    }

    private func normalizedWeatherCondition(_ condition: String) -> String {
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "基础闹钟" {
            return "天气未参与"
        }
        return trimmed
    }
}

struct WeatherAlarmWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: WeatherAlarmWidgetEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .padding(family == .systemMedium ? 12 : 10)
        .containerBackground(for: .widget) {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.56),
                    .init(color: Color(red: 0.97, green: 0.99, blue: 0.98), location: 0.82),
                    .init(color: Color(red: 0.94, green: 0.98, blue: 0.96), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                alarmGlyph(size: 26, symbolSize: 12)

                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.alarmTitle)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Text(entry.dayText)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(entry.hasStatus ? accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.scheduledWakeUpTimeText)
                    .font(.system(size: 37, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: entry.advanceMinutes > 0 ? "hourglass.bottomhalf.filled" : "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(totalAdvanceText)
                        .font(.system(size: 9.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(accentColor)

                if entry.advanceMinutes > 0 {
                    Text("基础 \(entry.baseWakeUpTimeText)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                accentColor.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 0.8)
            }

            HStack(spacing: 7) {
                signalPill(
                    icon: "cloud.rain.fill",
                    value: compactAdjustmentText(minutes: entry.weatherAdvanceMinutes),
                    color: weatherBlue
                )
                signalPill(
                    icon: "car.fill",
                    value: compactAdjustmentText(minutes: entry.routeAdvanceMinutes),
                    color: routeMint
                )
            }
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    alarmGlyph(size: 29, symbolSize: 13)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.alarmTitle)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                        Text(entry.dayText)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.scheduledWakeUpTimeText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.74)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: entry.advanceMinutes > 0 ? "hourglass.bottomhalf.filled" : "checkmark.circle.fill")
                    Text(totalAdvanceText)
                        .lineLimit(1)
                }
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(accentColor)

                Text(baseTimeText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                accentColor.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 0.8)
            }

            VStack(spacing: 8) {
                weatherGlassCard

                HStack(spacing: 8) {
                    signalCard(
                        title: "天气",
                        icon: "cloud.rain.fill",
                        value: adjustmentText(minutes: entry.weatherAdvanceMinutes),
                        color: weatherBlue
                    )
                    signalCard(
                        title: "路径",
                        icon: "car.fill",
                        value: adjustmentText(minutes: entry.routeAdvanceMinutes),
                        color: routeMint
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var weatherGlassCard: some View {
        HStack(spacing: 8) {
            Image(systemName: weatherSymbolName)
                .font(.system(size: 25, weight: .semibold))
                .symbolRenderingMode(.multicolor)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.weatherCondition)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(
                    entry.hasStatus
                        ? "降水 \(entry.precipitationChancePercent)%"
                        : "打开应用完成更新"
                )
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            weatherBlue.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 0.8)
        }
    }

    private func alarmGlyph(size: CGFloat, symbolSize: CGFloat) -> some View {
        Image(systemName: entry.alarmIconName)
            .font(.system(size: symbolSize, weight: .bold))
            .foregroundStyle(accentColor)
            .frame(width: size, height: size)
            .background(accentColor.opacity(0.13), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.78), lineWidth: 0.8)
            }
            .widgetAccentable()
    }

    private func signalPill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(color)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .font(.system(size: 9, weight: .bold))
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .background(color.opacity(0.075), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.72), lineWidth: 0.8)
        }
    }

    private func signalCard(title: String, icon: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 9.5, weight: .bold))

            Text(value)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            color.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 0.8)
        }
    }

    private var totalAdvanceText: String {
        guard entry.hasStatus else {
            return "等待 App 同步"
        }
        return entry.advanceMinutes > 0
            ? "提前 \(entry.advanceMinutes) 分钟"
            : "不用提前"
    }

    private func compactAdjustmentText(minutes: Int) -> String {
        minutes > 0 ? "\(minutes) 分钟" : "不用提前"
    }

    private var baseTimeText: String {
        guard entry.hasStatus, entry.advanceMinutes > 0 else {
            return entry.hasStatus ? "基础时间相同" : "等待 App 同步"
        }
        return "基础 \(entry.baseWakeUpTimeText)"
    }

    private func adjustmentText(minutes: Int) -> String {
        minutes > 0 ? "提前 \(minutes) 分钟" : "不用提前"
    }

    private var accentColor: Color {
        let colors: [Color] = [
            Color(red: 0.18, green: 0.74, blue: 0.87),
            Color(red: 0.27, green: 0.77, blue: 0.55),
            Color(red: 0.36, green: 0.59, blue: 0.96),
            Color(red: 0.47, green: 0.47, blue: 0.94),
            Color(red: 0.70, green: 0.48, blue: 0.92),
            Color(red: 0.19, green: 0.69, blue: 0.91),
            Color(red: 0.20, green: 0.79, blue: 0.67),
            Color(red: 0.12, green: 0.72, blue: 0.76),
            Color(red: 0.37, green: 0.65, blue: 0.94),
            Color(red: 0.31, green: 0.74, blue: 0.61),
            Color(red: 0.96, green: 0.48, blue: 0.38),
            Color(red: 0.98, green: 0.66, blue: 0.29),
            Color(red: 0.94, green: 0.48, blue: 0.64),
            Color(red: 0.94, green: 0.75, blue: 0.25),
            Color(red: 0.72, green: 0.51, blue: 0.88),
            Color(red: 0.96, green: 0.61, blue: 0.31)
        ]
        return colors[entry.alarmThemeIndex % colors.count]
    }

    private var weatherBlue: Color {
        Color(red: 0.18, green: 0.72, blue: 0.91)
    }

    private var routeMint: Color {
        Color(red: 0.16, green: 0.76, blue: 0.59)
    }

    private var weatherSymbolName: String {
        let condition = entry.weatherCondition.lowercased()
        if condition.contains("雷") || condition.contains("storm") {
            return "cloud.bolt.rain.fill"
        }
        if condition.contains("雪") || condition.contains("snow") {
            return "cloud.snow.fill"
        }
        if condition.contains("雨") || condition.contains("rain") || condition.contains("drizzle") {
            return "cloud.rain.fill"
        }
        if condition.contains("雾") || condition.contains("霾") || condition.contains("fog") || condition.contains("haze") {
            return "cloud.fog.fill"
        }
        if condition.contains("阴") || condition.contains("cloudy") || condition.contains("overcast") {
            return "cloud.fill"
        }
        if condition.contains("云") || condition.contains("cloud") {
            return "cloud.sun.fill"
        }
        return entry.hasStatus ? "sun.max.fill" : "cloud.sun.fill"
    }

    private var accessibilitySummary: String {
        guard entry.hasStatus else {
            return "SmartWake 暂无启用闹钟"
        }
        return "\(entry.alarmTitle)，\(entry.dayText) \(entry.scheduledWakeUpTimeText) 响铃，\(entry.advanceMinutes > 0 ? "提前 \(entry.advanceMinutes) 分钟" : "不用提前")，天气\(adjustmentText(minutes: entry.weatherAdvanceMinutes))，路径\(adjustmentText(minutes: entry.routeAdvanceMinutes))"
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
        .configurationDisplayName("SmartWake 智能闹钟")
        .description("显示响铃时间、天气、总提前时间和路径情况。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private extension DateFormatter {
    static let weatherAlarmWidgetTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let weatherAlarmWidgetDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 E"
        return formatter
    }()
}
