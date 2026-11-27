import Foundation

/// 界面语言设置。
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case zhHans
    case en
    case ja

    var id: String { rawValue }

    /// 选项名用各自的语言书写（业内惯例），看不懂当前界面语言的人也能找到自己的语言。
    var nativeName: String {
        switch self {
        case .system: return L("跟随系统")
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    var resolved: ResolvedLanguage {
        switch self {
        case .zhHans: return .zh
        case .en: return .en
        case .ja: return .ja
        case .system:
            for preferred in Locale.preferredLanguages {
                let code = preferred.lowercased()
                if code.hasPrefix("zh") { return .zh }
                if code.hasPrefix("ja") { return .ja }
                if code.hasPrefix("en") { return .en }
            }
            return .en
        }
    }
}

enum ResolvedLanguage: String {
    case zh, en, ja

    var locale: Locale {
        switch self {
        case .zh: return Locale(identifier: "zh-Hans")
        case .en: return Locale(identifier: "en")
        case .ja: return Locale(identifier: "ja")
        }
    }
}

/// 应用内本地化。
///
/// 为什么不用 String Catalog / .lproj：
/// 1. 构建环境只有 Command Line Tools，无法编译 .xcstrings；SwiftPM 资源包也不适合手工组装的 .app。
/// 2. 需要在 App 内即时切换语言，系统的按 App 设置语言要重启才生效。
///
/// 做法：中文原文作为 key，英文、日文各一张表（Localization/Strings.*.swift）。
/// 界面渲染时现查，切换语言后所有观察 AppModel 的视图会重新渲染。缺翻译时回退到中文，
/// `scripts/check-l10n.sh` 会检查遗漏。
enum L10n {
    /// 只在主线程读写。
    nonisolated(unsafe) static var current: ResolvedLanguage = .zh

    static var locale: Locale { current.locale }

    static func lookup(_ key: String) -> String {
        switch current {
        case .zh: return key
        case .en: return L10nTables.en[key] ?? key
        case .ja: return L10nTables.ja[key] ?? key
        }
    }

    // MARK: 日期格式，跟随界面语言而不是系统语言

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .standard).locale(locale))
    }

    static func relative(_ date: Date) -> String {
        var style = Date.RelativeFormatStyle(presentation: .named)
        style.locale = locale
        return date.formatted(style)
    }
}

/// 翻译表命名空间，内容见 Localization/Strings.en.swift、Strings.ja.swift。
enum L10nTables {}

/// 取当前语言的文案。key 为中文原文。
func L(_ key: String) -> String {
    L10n.lookup(key)
}

/// 带参数的文案，key 中用 %@ / %d / %.1f，需要调换顺序时用 %1$@ 这样的位置参数。
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.lookup(key), locale: L10n.locale, arguments: args)
}
