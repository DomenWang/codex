import AVFoundation
import Foundation

enum OrdinaryAlarmDismissChallenge: String, Codable, CaseIterable, Identifiable {
    case none
    case shake
    case math
    case steps

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .none:
            return "直接关闭"
        case .shake:
            return "摇一摇"
        case .math:
            return "算术题"
        case .steps:
            return "起身走动"
        }
    }
}

enum AlarmSoundCollection: String, CaseIterable, Identifiable {
    case fresh = "清新"
    case crystal = "水晶"
    case energetic = "动感"
    case ambient = "氛围"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .fresh: return "leaf.fill"
        case .crystal: return "diamond.fill"
        case .energetic: return "bolt.fill"
        case .ambient: return "moon.stars.fill"
        }
    }
}

enum AlarmSoundChoice: String, Codable, CaseIterable, Identifiable {
    case systemDefault
    case radar
    case apex
    case beacon
    case bulletin
    case byTheSeaside
    case chimes
    case constellation
    case cosmic
    case crystals
    case hillside
    case illuminate
    case nightOwl
    case opening
    case playtime
    case presto
    case ripples
    case sencha
    case silk
    case slowRise
    case summit
    case twinkle
    case uplift
    case waves

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .systemDefault:
            return "SmartWake 默认"
        case .radar:
            return "晨光脉冲"
        case .apex:
            return "山巅信号"
        case .beacon:
            return "远航灯塔"
        case .bulletin:
            return "清晨提示"
        case .byTheSeaside:
            return "海岸微风"
        case .chimes:
            return "琉璃钟声"
        case .constellation:
            return "星轨"
        case .cosmic:
            return "深空"
        case .crystals:
            return "水晶雨"
        case .hillside:
            return "山谷回声"
        case .illuminate:
            return "光束"
        case .nightOwl:
            return "夜航"
        case .opening:
            return "启程"
        case .playtime:
            return "像素早晨"
        case .presto:
            return "急速节拍"
        case .ripples:
            return "涟漪"
        case .sencha:
            return "茶雾"
        case .silk:
            return "丝弦"
        case .slowRise:
            return "渐醒"
        case .summit:
            return "日出峰线"
        case .twinkle:
            return "星点"
        case .uplift:
            return "上扬"
        case .waves:
            return "潮汐"
        }
    }

    var collection: AlarmSoundCollection {
        switch self {
        case .systemDefault, .byTheSeaside, .hillside, .sencha, .silk, .slowRise, .waves:
            return .fresh
        case .chimes, .constellation, .crystals, .illuminate, .ripples, .twinkle:
            return .crystal
        case .radar, .apex, .beacon, .bulletin, .opening, .playtime, .presto, .summit, .uplift:
            return .energetic
        case .cosmic, .nightOwl:
            return .ambient
        }
    }

    var soundDescription: String {
        switch self {
        case .systemDefault: return "温和木琴 · 逐步升高"
        case .radar: return "双音脉冲 · 清晰直接"
        case .apex: return "明亮铜管 · 向上推进"
        case .beacon: return "低频灯塔 · 间隔提醒"
        case .bulletin: return "短促木琴 · 连续提示"
        case .byTheSeaside: return "海浪底色 · 远处钟声"
        case .chimes: return "层叠钟声 · 通透悠长"
        case .constellation: return "高音玻璃 · 星轨流动"
        case .cosmic: return "深空和弦 · 低频氛围"
        case .crystals: return "水晶颗粒 · 明亮下落"
        case .hillside: return "长笛旋律 · 山风背景"
        case .illuminate: return "渐亮和弦 · 柔和展开"
        case .nightOwl: return "低音丝弦 · 夜间氛围"
        case .opening: return "短号序曲 · 有力收束"
        case .playtime: return "像素方波 · 轻快跳跃"
        case .presto: return "快速拨弦 · 高频节奏"
        case .ripples: return "回声水滴 · 左右扩散"
        case .sencha: return "五声音阶 · 轻盈拨弦"
        case .silk: return "柔和丝弦 · 缓慢呼吸"
        case .slowRise: return "三段和弦 · 循序渐醒"
        case .summit: return "上行铜管 · 抵达顶点"
        case .twinkle: return "稀疏星点 · 高音闪烁"
        case .uplift: return "上扬木琴 · 明快积极"
        case .waves: return "潮汐白噪 · 长笛呼应"
        }
    }

    var bundledFileName: String {
        switch self {
        case .systemDefault:
            return "alarm_default.wav"
        case .radar:
            return "alarm_radar.wav"
        case .apex:
            return "alarm_apex.wav"
        case .beacon:
            return "alarm_beacon.wav"
        case .bulletin:
            return "alarm_bulletin.wav"
        case .byTheSeaside:
            return "alarm_by_the_seaside.wav"
        case .chimes:
            return "alarm_chimes.wav"
        case .constellation:
            return "alarm_constellation.wav"
        case .cosmic:
            return "alarm_cosmic.wav"
        case .crystals:
            return "alarm_crystals.wav"
        case .hillside:
            return "alarm_hillside.wav"
        case .illuminate:
            return "alarm_illuminate.wav"
        case .nightOwl:
            return "alarm_night_owl.wav"
        case .opening:
            return "alarm_opening.wav"
        case .playtime:
            return "alarm_playtime.wav"
        case .presto:
            return "alarm_presto.wav"
        case .ripples:
            return "alarm_ripples.wav"
        case .sencha:
            return "alarm_sencha.wav"
        case .silk:
            return "alarm_silk.wav"
        case .slowRise:
            return "alarm_slow_rise.wav"
        case .summit:
            return "alarm_summit.wav"
        case .twinkle:
            return "alarm_twinkle.wav"
        case .uplift:
            return "alarm_uplift.wav"
        case .waves:
            return "alarm_waves.wav"
        }
    }

    var bundledSubdirectory: String {
        "AlarmSounds"
    }

    func bundledFileName(loudVolumeEnabled: Bool) -> String {
        guard loudVolumeEnabled else {
            return bundledFileName
        }

        return bundledFileName.replacingOccurrences(of: ".wav", with: "_loud.wav")
    }

    func alarmKitSoundName(loudVolumeEnabled: Bool) -> String {
        bundledFileName(loudVolumeEnabled: loudVolumeEnabled)
    }
}

struct CustomAlarmSound: Codable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let fileName: String
    let duration: TimeInterval
    let createdAt: Date

    var durationText: String {
        let totalSeconds = max(1, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

enum AlarmSoundSelection: Equatable, Identifiable {
    case builtIn(AlarmSoundChoice)
    case custom(UUID)

    var id: String {
        switch self {
        case .builtIn(let choice):
            return "builtIn:\(choice.rawValue)"
        case .custom(let id):
            return "custom:\(id.uuidString)"
        }
    }

    var builtInFallback: AlarmSoundChoice {
        switch self {
        case .builtIn(let choice):
            return choice
        case .custom:
            return .systemDefault
        }
    }

    var customSoundID: UUID? {
        guard case .custom(let id) = self else {
            return nil
        }
        return id
    }

    var displayName: String {
        switch self {
        case .builtIn(let choice):
            return choice.displayName
        case .custom(let id):
            return CustomAlarmSoundStore.sound(id: id)?.displayName ?? "我的音频"
        }
    }
}

enum CustomAlarmSoundStoreError: LocalizedError {
    case unreadableFile
    case emptyAudio
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "无法读取这个音频文件，请换一个文件重试。"
        case .emptyAudio:
            return "这个音频没有可用内容。"
        case .conversionFailed:
            return "音频转换失败，请尝试 WAV、AIFF、CAF、M4A 或 MP3 文件。"
        }
    }
}

enum CustomAlarmSoundStore {
    static let maximumDuration: TimeInterval = 29

    private static let metadataFileName = "custom_alarm_sounds.json"
    private static let fileNamePrefix = "smartwake_custom_"
    private static let outputSampleRate: Double = 44_100

    static func sounds() -> [CustomAlarmSound] {
        let decoded = (try? Data(contentsOf: metadataURL()))
            .flatMap { try? JSONDecoder().decode([CustomAlarmSound].self, from: $0) }
            ?? []

        return decoded
            .filter { FileManager.default.fileExists(atPath: soundsDirectory().appendingPathComponent($0.fileName).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func sound(id: UUID) -> CustomAlarmSound? {
        sounds().first { $0.id == id }
    }

    static func audioURL(for id: UUID) -> URL? {
        guard let sound = sound(id: id) else {
            return nil
        }

        let url = soundsDirectory().appendingPathComponent(sound.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func alarmKitSoundName(for id: UUID) -> String? {
        sound(id: id)?.fileName
    }

    static func deleteSound(id: UUID) throws {
        guard let sound = sound(id: id) else {
            return
        }

        let fileManager = FileManager.default
        let url = soundsDirectory().appendingPathComponent(sound.fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let remainingSounds = sounds().filter { $0.id != id }
        let data = try JSONEncoder().encode(remainingSounds)
        try data.write(to: metadataURL(), options: .atomic)
    }

    static func importSound(from sourceURL: URL) async throws -> CustomAlarmSound {
        let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        return try await Task.detached(priority: .userInitiated) {
            try convertAndSaveSound(from: sourceURL)
        }.value
    }

    private static func convertAndSaveSound(from sourceURL: URL) throws -> CustomAlarmSound {
        let fileManager = FileManager.default
        let directory = soundsDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: metadataURL().deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw CustomAlarmSoundStoreError.unreadableFile
        }

        let inputFormat = inputFile.processingFormat
        guard inputFile.length > 0,
              inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0 else {
            throw CustomAlarmSoundStoreError.emptyAudio
        }

        let channelCount = min(inputFormat.channelCount, AVAudioChannelCount(2))
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: outputSampleRate,
            channels: channelCount,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw CustomAlarmSoundStoreError.conversionFailed
        }

        let id = UUID()
        let fileName = "\(fileNamePrefix)\(id.uuidString.lowercased()).caf"
        let destinationURL = directory.appendingPathComponent(fileName)
        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: false
            )
        } catch {
            throw CustomAlarmSoundStoreError.conversionFailed
        }

        let sourceFrameLimit = AVAudioFramePosition(
            min(
                Double(inputFile.length),
                maximumDuration * inputFormat.sampleRate
            )
        )
        let outputFrameLimit = AVAudioFramePosition(
            maximumDuration * outputFormat.sampleRate
        )
        let outputCapacity: AVAudioFrameCount = 4_096
        var suppliedInput = false
        var conversionError: Error?

        do {
            while outputFile.length < outputFrameLimit {
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: outputCapacity
                ) else {
                    throw CustomAlarmSoundStoreError.conversionFailed
                }

                var converterError: NSError?
                let status = converter.convert(to: outputBuffer, error: &converterError) {
                    requestedPackets,
                    inputStatus in
                    if suppliedInput {
                        suppliedInput = false
                        inputStatus.pointee = .noDataNow
                        return nil
                    }

                    let remainingFrames = sourceFrameLimit - inputFile.framePosition
                    guard remainingFrames > 0 else {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }

                    let requestedFrames = AVAudioFrameCount(
                        min(AVAudioFramePosition(requestedPackets), remainingFrames)
                    )
                    guard let inputBuffer = AVAudioPCMBuffer(
                        pcmFormat: inputFormat,
                        frameCapacity: requestedFrames
                    ) else {
                        inputStatus.pointee = .endOfStream
                        conversionError = CustomAlarmSoundStoreError.conversionFailed
                        return nil
                    }

                    do {
                        try inputFile.read(into: inputBuffer, frameCount: requestedFrames)
                    } catch {
                        inputStatus.pointee = .endOfStream
                        conversionError = error
                        return nil
                    }

                    guard inputBuffer.frameLength > 0 else {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }

                    suppliedInput = true
                    inputStatus.pointee = .haveData
                    return inputBuffer
                }

                if let conversionError {
                    throw conversionError
                }
                if let converterError {
                    throw converterError
                }
                if outputBuffer.frameLength > 0 {
                    let remainingOutputFrames = outputFrameLimit - outputFile.length
                    if AVAudioFramePosition(outputBuffer.frameLength) > remainingOutputFrames {
                        outputBuffer.frameLength = AVAudioFrameCount(remainingOutputFrames)
                    }
                    try outputFile.write(from: outputBuffer)
                }
                if status == .endOfStream {
                    break
                }
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw CustomAlarmSoundStoreError.conversionFailed
        }

        guard outputFile.length > 0 else {
            try? fileManager.removeItem(at: destinationURL)
            throw CustomAlarmSoundStoreError.emptyAudio
        }

        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sound = CustomAlarmSound(
            id: id,
            displayName: sourceName.isEmpty ? "我的音频" : sourceName,
            fileName: fileName,
            duration: min(
                maximumDuration,
                Double(outputFile.length) / outputFormat.sampleRate
            ),
            createdAt: Date()
        )
        var storedSounds = sounds()
        storedSounds.removeAll { $0.id == sound.id }
        storedSounds.insert(sound, at: 0)
        let data = try JSONEncoder().encode(storedSounds)
        try data.write(to: metadataURL(), options: .atomic)
        return sound
    }

    private static func soundsDirectory() -> URL {
        let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return libraryDirectory.appendingPathComponent("Sounds", isDirectory: true)
    }

    private static func metadataURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport
            .appendingPathComponent("SmartWake", isDirectory: true)
            .appendingPathComponent(metadataFileName)
    }
}

private enum AlarmWeekdayText {
    static func repeatSummaryText(for weekdays: [Int]) -> String {
        guard !weekdays.isEmpty else {
            return "仅一次"
        }

        if weekdays == [1, 2, 3, 4, 5, 6, 7] {
            return "每天"
        }

        if weekdays == [2, 3, 4, 5, 6] {
            return "工作日"
        }

        if weekdays == [1, 7] {
            return "周末"
        }

        return weekdays.map { weekdayShortName($0) }.joined(separator: " ")
    }

    static func normalizedWeekdays(_ weekdays: [Int]?) -> [Int] {
        Set((weekdays ?? []).filter { (1...7).contains($0) }).sorted()
    }

    static func nextDate(
        hour: Int,
        minute: Int,
        weekdays: [Int],
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        guard !weekdays.isEmpty else {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            components.second = 0

            return calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }

        for dayOffset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  candidate > now else {
                continue
            }

            if weekdays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
        }

        return nil
    }

    private static func weekdayShortName(_ weekday: Int) -> String {
        switch weekday {
        case 1:
            return "周日"
        case 2:
            return "周一"
        case 3:
            return "周二"
        case 4:
            return "周三"
        case 5:
            return "周四"
        case 6:
            return "周五"
        case 7:
            return "周六"
        default:
            return ""
        }
    }
}

struct OrdinaryAlarmSettings: Codable, Equatable, Identifiable {
    var id: UUID
    var alarmID: UUID
    var loudAlarmID: UUID?
    var hour: Int
    var minute: Int
    var isEnabled: Bool?
    var title: String?
    var repeatWeekdays: [Int]?
    var themeIndex: Int?
    var iconName: String?
    var snoozeMinutes: Int?
    var dismissChallenge: OrdinaryAlarmDismissChallenge?
    var soundChoice: AlarmSoundChoice?
    var customSoundID: UUID?
    var isLoudVolumeEnabled: Bool?
    var isWeatherAdjustmentEnabled: Bool
    var isCommuteAdjustmentEnabled: Bool
    var arrivalHour: Int?
    var arrivalMinute: Int?
    var commuteRoute: CommuteRoute?
    var commuteModeSuggestion: CommuteMode?

    init(
        id: UUID = UUID(),
        alarmID: UUID = UUID(),
        loudAlarmID: UUID? = nil,
        hour: Int,
        minute: Int,
        isEnabled: Bool = true,
        title: String? = nil,
        repeatWeekdays: [Int] = [],
        themeIndex: Int = 0,
        iconName: String? = nil,
        snoozeMinutes: Int = 9,
        dismissChallenge: OrdinaryAlarmDismissChallenge = .none,
        soundChoice: AlarmSoundChoice = .systemDefault,
        customSoundID: UUID? = nil,
        isLoudVolumeEnabled: Bool = false,
        isWeatherAdjustmentEnabled: Bool = false,
        isCommuteAdjustmentEnabled: Bool = false,
        arrivalHour: Int? = nil,
        arrivalMinute: Int? = nil,
        commuteRoute: CommuteRoute? = nil,
        commuteModeSuggestion: CommuteMode? = nil
    ) {
        self.id = id
        self.alarmID = alarmID
        self.loudAlarmID = loudAlarmID
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.title = title
        self.repeatWeekdays = repeatWeekdays
        self.themeIndex = themeIndex
        self.iconName = iconName
        self.snoozeMinutes = snoozeMinutes
        self.dismissChallenge = dismissChallenge
        self.soundChoice = soundChoice
        self.customSoundID = customSoundID
        self.isLoudVolumeEnabled = isLoudVolumeEnabled
        self.isWeatherAdjustmentEnabled = isWeatherAdjustmentEnabled
        self.isCommuteAdjustmentEnabled = isCommuteAdjustmentEnabled
        self.arrivalHour = arrivalHour
        self.arrivalMinute = arrivalMinute
        self.commuteRoute = commuteRoute
        self.commuteModeSuggestion = commuteModeSuggestion
    }

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var usesSmartTiming: Bool {
        isWeatherAdjustmentEnabled || isCommuteAdjustmentEnabled
    }

    var hasArrivalTime: Bool {
        guard let arrivalHour,
              let arrivalMinute else {
            return false
        }

        return (0...23).contains(arrivalHour) && (0...59).contains(arrivalMinute)
    }

    var arrivalTimeText: String {
        guard hasArrivalTime,
              let arrivalHour,
              let arrivalMinute else {
            return "未设置"
        }

        return String(format: "%02d:%02d", arrivalHour, arrivalMinute)
    }

    var effectiveIsEnabled: Bool {
        isEnabled ?? true
    }

    var effectiveTitle: String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? "其他闹钟" : trimmedTitle
    }

    var alarmPresentationTitle: String {
        guard isCommuteAdjustmentEnabled,
              let commuteModeSuggestion else {
            return effectiveTitle
        }

        return "\(effectiveTitle) · 建议\(commuteModeSuggestion.displayName)"
    }

    var effectiveRepeatWeekdays: [Int] {
        AlarmWeekdayText.normalizedWeekdays(repeatWeekdays)
    }

    var effectiveThemeIndex: Int {
        if let themeIndex {
            return max(0, themeIndex)
        }

        // Older saved alarms predate theme persistence. Derive a stable theme
        // from the UUID so they do not all fall back to the same color.
        return id.uuidString.utf8.reduce(0) { partialResult, byte in
            (partialResult &* 31 &+ Int(byte)) & 0x7fff_ffff
        }
    }

    var effectiveIconName: String {
        let trimmedIconName = iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedIconName.isEmpty ? "alarm" : trimmedIconName
    }

    var effectiveSnoozeMinutes: Int {
        let minutes = snoozeMinutes ?? 9
        return max(0, min(30, minutes))
    }

    var effectiveDismissChallenge: OrdinaryAlarmDismissChallenge {
        dismissChallenge ?? .none
    }

    var effectiveSoundChoice: AlarmSoundChoice {
        soundChoice ?? .systemDefault
    }

    var effectiveSoundSelection: AlarmSoundSelection {
        guard let customSoundID,
              CustomAlarmSoundStore.sound(id: customSoundID) != nil else {
            return .builtIn(effectiveSoundChoice)
        }
        return .custom(customSoundID)
    }

    var effectiveIsLoudVolumeEnabled: Bool {
        isLoudVolumeEnabled ?? false
    }

    var repeatSummaryText: String {
        AlarmWeekdayText.repeatSummaryText(for: effectiveRepeatWeekdays)
    }

    var snoozeSummaryText: String {
        effectiveSnoozeMinutes == 0 ? "关闭稍后提醒" : "稍后提醒 \(effectiveSnoozeMinutes) 分钟"
    }

    func nextBaseWakeUpDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        AlarmWeekdayText.nextDate(
            hour: hour,
            minute: minute,
            weekdays: effectiveRepeatWeekdays,
            after: now,
            calendar: calendar
        )
    }

    func targetArrivalDate(for baseWakeUpDate: Date, calendar: Calendar = .current) -> Date? {
        guard hasArrivalTime,
              let arrivalHour,
              let arrivalMinute,
              let sameDayArrival = calendar.date(
                bySettingHour: arrivalHour,
                minute: arrivalMinute,
                second: 0,
                of: baseWakeUpDate
              ) else {
            return nil
        }

        if sameDayArrival > baseWakeUpDate {
            return sameDayArrival
        }

        return calendar.date(
            byAdding: .day,
            value: 1,
            to: sameDayArrival
        ) ?? sameDayArrival.addingTimeInterval(24 * 60 * 60)
    }
}

/// 用户配置的“正常起床闹钟”。
///
/// 这里故意不提供默认起床时间，因为需求明确要求“不要写死闹钟时间”。
/// App 的设置页应在用户选择时间后，把这个模型保存到 `AlarmSettingsStore`。
struct AlarmSettings: Codable, Equatable {
    /// AlarmKit schedule 使用的稳定 ID。
    ///
    /// 同一个 ID 代表同一个业务闹钟。更新天气提前量时，用同一个 ID 重新 schedule，
    /// 系统就能把它当作同一个闹钟的更新，而不是每天创建一堆新闹钟。
    var alarmID: UUID
    var wakeUpLoudAlarmID: UUID? = nil

    /// 用户设置的正常起床时间，只保存时分，不保存日期。
    var wakeUpHour: Int
    var wakeUpMinute: Int
    var wakeUpTitle: String?
    var wakeUpRepeatWeekdays: [Int]?
    var wakeUpThemeIndex: Int?
    var wakeUpIconName: String?
    var wakeUpDismissChallenge: OrdinaryAlarmDismissChallenge?
    var wakeUpSoundChoice: AlarmSoundChoice? = nil
    var wakeUpCustomSoundID: UUID? = nil
    var isWakeUpLoudVolumeEnabled: Bool? = nil
    /// 起床闹钟本身是否启用。
    ///
    /// 这是独立于天气/路径功能的总开关。旧版本没有这个字段时默认开启，
    /// 避免升级后把用户原本已经安排好的起床闹钟意外关闭。
    var isWakeUpAlarmEnabled: Bool? = nil
    var wakeUpArrivalHour: Int? = nil
    var wakeUpArrivalMinute: Int? = nil

    /// 用户选择是否启用天气闹钟。
    var isEnabled: Bool

    /// 用户选择是否让地图/通勤耗时参与闹钟提前量。
    ///
    /// 旧版本数据没有这个字段时默认关闭，避免在用户未明确开启前使用通勤路线影响闹钟时间。
    var isCommuteAdjustmentEnabled: Bool?

    /// 可选通勤路线。
    ///
    /// 如果用户没有配置通勤路线，AlarmManager 会跳过 TransitService，
    /// 只使用天气逻辑。这里不写死任何起点/终点。
    var commuteRoute: CommuteRoute?

    /// 用户可配置的雨天提前规则。
    ///
    /// 旧版本数据没有这个字段时，业务层会使用 `WeatherAdjustmentSettings.default`。
    var weatherAdjustmentSettings: WeatherAdjustmentSettings?

    /// 用户额外添加的普通闹钟。
    ///
    /// 每个普通闹钟都有自己的 AlarmKit ID，并可单独选择天气提前和通勤路径提前。
    var ordinaryAlarms: [OrdinaryAlarmSettings]?

    var effectiveWeatherAdjustmentSettings: WeatherAdjustmentSettings {
        weatherAdjustmentSettings ?? .default
    }

    var effectiveIsCommuteAdjustmentEnabled: Bool {
        isCommuteAdjustmentEnabled ?? false
    }

    var effectiveOrdinaryAlarms: [OrdinaryAlarmSettings] {
        ordinaryAlarms ?? []
    }

    var effectiveWakeUpTitle: String {
        let trimmedTitle = wakeUpTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? "起床闹钟" : trimmedTitle
    }

    var effectiveWakeUpThemeIndex: Int {
        max(0, wakeUpThemeIndex ?? 0)
    }

    var effectiveWakeUpIconName: String {
        let trimmedIconName = wakeUpIconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedIconName.isEmpty ? "alarm.fill" : trimmedIconName
    }

    var effectiveWakeUpDismissChallenge: OrdinaryAlarmDismissChallenge {
        wakeUpDismissChallenge ?? .none
    }

    var effectiveWakeUpSoundChoice: AlarmSoundChoice {
        wakeUpSoundChoice ?? .systemDefault
    }

    var effectiveWakeUpSoundSelection: AlarmSoundSelection {
        guard let wakeUpCustomSoundID,
              CustomAlarmSoundStore.sound(id: wakeUpCustomSoundID) != nil else {
            return .builtIn(effectiveWakeUpSoundChoice)
        }
        return .custom(wakeUpCustomSoundID)
    }

    var effectiveIsWakeUpLoudVolumeEnabled: Bool {
        isWakeUpLoudVolumeEnabled ?? false
    }

    var effectiveIsWakeUpAlarmEnabled: Bool {
        isWakeUpAlarmEnabled ?? true
    }

    var effectiveWakeUpRepeatWeekdays: [Int] {
        AlarmWeekdayText.normalizedWeekdays(wakeUpRepeatWeekdays)
    }

    var wakeUpRepeatSummaryText: String {
        AlarmWeekdayText.repeatSummaryText(for: effectiveWakeUpRepeatWeekdays)
    }

    var hasWakeUpArrivalTime: Bool {
        guard let wakeUpArrivalHour,
              let wakeUpArrivalMinute else {
            return false
        }

        return (0...23).contains(wakeUpArrivalHour) && (0...59).contains(wakeUpArrivalMinute)
    }

    var wakeUpArrivalTimeText: String {
        guard hasWakeUpArrivalTime,
              let wakeUpArrivalHour,
              let wakeUpArrivalMinute else {
            return "未设置"
        }

        return String(format: "%02d:%02d", wakeUpArrivalHour, wakeUpArrivalMinute)
    }

    /// 根据“今天/明天”的日期计算下一次基础起床时间。
    /// - Parameter now: 当前时间，默认使用系统当前时间。
    /// - Returns: 下一次用户设置的起床 Date。
    func nextBaseWakeUpDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        AlarmWeekdayText.nextDate(
            hour: wakeUpHour,
            minute: wakeUpMinute,
            weekdays: effectiveWakeUpRepeatWeekdays,
            after: now,
            calendar: calendar
        )
    }

    func targetWakeUpArrivalDate(for baseWakeUpDate: Date, calendar: Calendar = .current) -> Date? {
        guard hasWakeUpArrivalTime,
              let wakeUpArrivalHour,
              let wakeUpArrivalMinute,
              let sameDayArrival = calendar.date(
                bySettingHour: wakeUpArrivalHour,
                minute: wakeUpArrivalMinute,
                second: 0,
                of: baseWakeUpDate
              ) else {
            return nil
        }

        if sameDayArrival > baseWakeUpDate {
            return sameDayArrival
        }

        return calendar.date(byAdding: .day, value: 1, to: sameDayArrival)
            ?? sameDayArrival.addingTimeInterval(24 * 60 * 60)
    }
}
