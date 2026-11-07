import Foundation

/// 极简的双语字符串表。
///
/// 只有中/英两种界面语言，字符串量很小，所以不引入 `.strings` 资源包，
/// 直接在调用点给出两种文案，减少一处资源加载失败的可能。
public enum L10n {
    public enum Language: String, Equatable, Sendable {
        case zhHans = "zh-Hans"
        case en = "en"
    }

    /// 测试与 `--lang` 参数用的强制语言；为 nil 时按系统首选语言判断。
    public static var forcedLanguage: Language?

    public static var language: Language {
        if let forcedLanguage { return forcedLanguage }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .zhHans : .en
    }

    /// 按当前语言二选一。
    public static func tr(_ zhHans: String, _ en: String) -> String {
        language == .zhHans ? zhHans : en
    }
}
