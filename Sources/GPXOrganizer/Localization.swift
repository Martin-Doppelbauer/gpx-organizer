import SwiftUI
import Foundation

// Languages of the program. The texts live in Resources/Localization/<language>.lproj/Localizable.strings; the English
// text itself is the key, so English is the fallback for everything that is not translated (yet).
//
//  • SwiftUI literals (Text("…"), Button("…"), Toggle("…") …) are looked up automatically.
//  • Everything else (menus made with AppKit, alerts, status messages, text built from parts) goes through L("…").
//
// The language chosen in Settings is written to the preferences of the program (AppleLanguages) and takes effect
// at the next start, like the system language does.

/// Looks up a text in the language of the program.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Looks up a text with placeholders (%@, %d, %.1f …) and fills them in.
func L(_ key: String, _ args: CVarArg...) -> String { String(format: NSLocalizedString(key, comment: ""), arguments: args) }

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, de, fr, it, es, ptBR = "pt-BR"
    var id: String { rawValue }

    /// Every language is shown in its own name.
    var nativeName: String {
        switch self {
        case .system: return ""
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .it: return "Italiano"
        case .es: return "Español"
        case .ptBR: return "Português (Brasil)"
        }
    }

    /// The languages the program really has texts for (the folders in the program), plus "system".
    static var available: [AppLanguage] {
        let have = Set(Bundle.main.localizations)
        return [.system] + allCases.filter { $0 != .system && have.contains($0.rawValue) }
    }

    static var chosen: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system }
        set {
            let d = UserDefaults.standard
            d.set(newValue.rawValue, forKey: "appLanguage")
            if newValue == .system { d.removeObject(forKey: "AppleLanguages") }      // back to the system's order of languages
            else { d.set([newValue.rawValue], forKey: "AppleLanguages") }
        }
    }
}
