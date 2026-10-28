import Foundation

/// Chooses the app language from the first preferred language only. iOS normally
/// scans the whole preference list, which can select Chinese when Italian is first
/// and Chinese is second; this app intentionally falls back to English instead.
enum AppLocalization {
    static func identifier(for preferredLanguages: [String]) -> String {
        guard let first = preferredLanguages.first else { return "en" }
        let languageCode = Locale(identifier: first).languageCode
        if languageCode == "ar" { return "ar" }
        if languageCode == "zh" {
            return Bundle.preferredLocalizations(
                from: ["zh-Hans", "zh-Hant"], forPreferences: [first]
            ).first ?? "zh-Hans"
        }
        return "en"
    }

    static var identifier: String { AppLanguageStore.shared.languageCode }
    static var locale: Locale { AppLanguageStore.shared.locale }

    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: .main, locale: locale)
    }
}
