import Foundation

enum AppGroupUserDefaults {
    static let identifier = "group.com.domenx.SmartWake"

    static var shared: UserDefaults {
        guard let defaults = UserDefaults(suiteName: identifier) else {
            assertionFailure("SmartWake App Group 不可用，请检查主 App 与 Widget 的签名权利。")
            return .standard
        }
        return defaults
    }
}
