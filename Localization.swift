import Foundation

/// 语言选择逻辑（与 Bundle / UserDefaults 解耦，便于测试）。
enum LanguageResolver {
    static let supported = ["en", "zh-Hans"]

    static func resolve(selected: String?, preferredLanguages: [String]) -> String {
        if let selected, supported.contains(selected) { return selected }
        if let first = preferredLanguages.first, first.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }
}