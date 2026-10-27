// Ürünün kalbi: ses nerede çalsın?
//
// Kulaklık hep iPhone'a bağlı. iPhone'da başka bir uygulama ses çalmaya başlarsa (Instagram, YouTube…)
// telefon öncelik alır: PC sesi kısılır, PC'deki medya (isteğe bağlı) duraklatılır. O ses bitince kısa bir
// beklemeden sonra (videolar arasındaki boşluklarda gidip gelmesin) PC sesi geri gelir.
//
// iOS başka bir uygulamanın sesini arka plandan kesmemize izin vermez; bu yüzden ters yön (telefonda müzik
// çalarken PC'ye dönmek) kullanıcının AirPods'a bir dokunuşuyla olur: telefon müziği durur → PC gelir.

import Foundation

public enum GecisModu: String, Codable, CaseIterable, Sendable {
    /// Telefon sesi gelince PC tamamen susar.
    case sustur
    /// PC arka planda kısık kalır.
    case kis
    /// Hiçbir şey yapma: ikisi birlikte çalar.
    case karistir
}

public enum OdakOlayi: Equatable, Sendable {
    case telefonaGecti
    case pcyeDondu
}

public final class OdakMotoru {
    public var otomatik = true
    public var mod = GecisModu.sustur
    public var kisSeviyesi: Float = 0.25
    /// Telefon sesi bittikten sonra PC'ye dönmeden önce beklenen süre (sn).
    public var donusGecikmesi: Double = 0.6

    public private(set) var telefonda = false
    private var susmaAni: Double?

    public init() {}

    /// Düzenli aralıkla (≈5/sn) çağrılır. Durum değiştiyse olayı döner.
    public func guncelle(digerSesCaliyor: Bool, simdi: Double) -> OdakOlayi? {
        guard otomatik, mod != .karistir else {
            susmaAni = nil
            if telefonda { telefonda = false; return .pcyeDondu }
            return nil
        }
        if digerSesCaliyor {
            susmaAni = nil
            if !telefonda { telefonda = true; return .telefonaGecti }
            return nil
        }
        guard telefonda else { return nil }
        if let s = susmaAni {
            if simdi - s >= donusGecikmesi {
                telefonda = false
                susmaAni = nil
                return .pcyeDondu
            }
        } else {
            susmaAni = simdi
        }
        return nil
    }

    /// PC sesine uygulanacak kazanç.
    public var pcKazanci: Float {
        guard telefonda else { return 1 }
        switch mod {
        case .sustur: return 0
        case .kis: return kisSeviyesi
        case .karistir: return 1
        }
    }
}
