import SwiftUI

/// Prosta lokalizacja PL/EN. Język trzymany w UserDefaults ("lang"); widoki obserwują go przez @AppStorage.
enum Lang {
    static var current: String {
        if let l = UserDefaults.standard.string(forKey: "lang") { return l }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("pl") ? "pl" : "en"
    }
}

func tr(_ pl: String, _ en: String) -> String { Lang.current == "pl" ? pl : en }
