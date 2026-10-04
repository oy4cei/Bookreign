import SwiftUI
import Observation

/// Interface settings are independent of the library and its backups.
@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    private static let languageKey = "polka.interfaceLanguage"
    private static let appearanceKey = "polka.appearance"
    // Keep the original key so existing users retain their library layout.
    private static let libraryGridKey = "libraryGrid"
    private let defaults: UserDefaults

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.languageKey) }
    }
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    var libraryGrid: Bool {
        didSet { defaults.set(libraryGrid, forKey: Self.libraryGridKey) }
    }

    var locale: Locale { Locale(identifier: language.rawValue) }

    init(defaults suppliedDefaults: UserDefaults? = nil) {
        let defaults: UserDefaults
        if let suppliedDefaults {
            defaults = suppliedDefaults
        } else {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing") {
                // Test resets must never fall back to the user's real preferences.
                defaults = UserDefaults(suiteName: "Polka.UITesting.Preferences")!
                if arguments.contains("--reset-preferences") {
                    defaults.removeObject(forKey: Self.languageKey)
                    defaults.removeObject(forKey: Self.appearanceKey)
                    defaults.removeObject(forKey: Self.libraryGridKey)
                }
            } else {
                defaults = .standard
            }
            #else
            defaults = .standard
            #endif
        }
        self.defaults = defaults
        language = defaults.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .ru
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
        libraryGrid = defaults.object(forKey: Self.libraryGridKey) as? Bool ?? true
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case uk, en, ru
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .uk: return "Українська"
        case .en: return "English"
        case .ru: return "Русский"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .system: return L("Как на устройстве")
        case .light: return L("Светлая")
        case .dark: return L("Тёмная")
        }
    }
}

enum AppVersion {
    static var displayString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
