// Arayüz dili: iPhone (ya da yalnız bu uygulama için seçilen dil) Türkçeyse Türkçe, değilse İngilizce.
// Bundle.main uygulamanın paketidir; tr.lproj ve en.lproj klasörleri hangi dillerin desteklendiğini söyler.
// SYP_DIL=tr|en ortam değişkeni seçimi ezer (Linux denemeleri ve ekran görüntüleri için).

import Foundation

public enum Dil {
    public static let turkce: Bool = {
        if let d = ProcessInfo.processInfo.environment["SYP_DIL"] { return d.hasPrefix("tr") }
        return (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("tr")
    }()
}

/// İki dilli metin: `L("Kapalı", "Off")`.
public func L(_ tr: String, _ en: String) -> String { Dil.turkce ? tr : en }
