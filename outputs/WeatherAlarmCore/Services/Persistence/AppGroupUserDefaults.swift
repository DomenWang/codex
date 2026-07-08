import Foundation

enum AppGroupUserDefaults {
    // TODO: 在 Apple Developer 和 Xcode Signing & Capabilities 中启用同名 App Group。
    static let identifier = "group.com.domenx.SmartWake"

    static var shared: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
