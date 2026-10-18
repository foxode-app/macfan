import Foundation

/// The app's display language.
///
/// It is saved the way System Settings saves a per-app language — as `AppleLanguages` in the app's defaults — so
/// the two always agree. SwiftUI views switch at once through their locale; text that AppKit provides, such as
/// window titles, follows after a restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"

    var id: Self { self }

    /// The same in every language, so either option can be found whichever is active.
    var label: String {
        switch self {
        case .japanese: "🇯🇵 Japanese"
        case .english: "🇬🇧 English"
        }
    }

    /// The language with the user's region, so numbers and units keep their regional format.
    var locale: Locale {
        Locale(languageCode: Locale.LanguageCode(rawValue), languageRegion: Locale.current.region)
    }

    /// The saved language, or the system's when the app has none of its own.
    static var saved: AppLanguage {
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en"
        return preferred.hasPrefix("ja") ? .japanese : .english
    }

    /// The language the app's resources were loaded in at launch.
    static var atLaunch: AppLanguage? {
        Bundle.main.preferredLocalizations.first.flatMap(AppLanguage.init(rawValue:))
    }

    func save() {
        UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
    }
}
