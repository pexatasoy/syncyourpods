// Kullanıcı ayarları (iPhone'da UserDefaults'ta JSON olarak durur) ve ekolayzer hazır ayarları.

import Foundation

public enum Yukseltici: String, Codable, CaseIterable, Sendable {
    case kapali, hafif, guclu
}

public struct Ayarlar: Codable, Equatable, Sendable {
    // Ses
    public var ses: Float = 0.8
    public var denge: Float = 0
    public var mono = false
    public var yukseltici = Yukseltici.kapali
    // Ekolayzer
    public var eqAcik = false
    public var eqHazir = "duz"
    public var eqOzel: [Float] = Array(repeating: 0, count: Ekolayzer.bantlar.count)
    // Geçiş
    public var otomatikGecis = true
    public var gecisModu = GecisModu.sustur
    public var kisSeviyesi: Float = 0.25
    public var donusGecikmesi = 0.6
    public var gecisSuresi = 0.25
    public var medyaDuraklat = true
    /// Bağlıyken PC'nin kendi hoparlörü/kulaklığı sussun.
    public var pcSesiniKapat = true
    // Gecikme
    public var gecikme = GecikmeModu.enDusuk
    /// Deneysel: AirPods'u görüşme (HFP) yoluna alır. Bluetooth gecikmesi çok düşer, ses mono ve daha boğuk olur.
    public var gorusmeKipi = false
    // Mikrofon
    public var mikAcik = false
    public var mikYuksekKalite = true
    public var mikSesYalitimi = false
    // Bağlantı
    public var otomatikBaglan = true
    public var sonPC: String?
    // Genel
    public var titresim = true
    /// Tanılama: yalnız "öncelikli ses" ipucu yerine telefondaki HER sesi (oyun, uygulama sesleri) sayar.
    public var genisAlgilama = false
    /// Kayıt biçimi sürümü: varsayılan değişince eski kayıtları taşımak için.
    public var surum = 2

    public init() {}

    // Yeni alan eklenince eski kayıt bozulmasın: eksik alan varsayılanla gelir.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = Ayarlar()
        ses = try c.decodeIfPresent(Float.self, forKey: .ses) ?? v.ses
        denge = try c.decodeIfPresent(Float.self, forKey: .denge) ?? v.denge
        mono = try c.decodeIfPresent(Bool.self, forKey: .mono) ?? v.mono
        yukseltici = try c.decodeIfPresent(Yukseltici.self, forKey: .yukseltici) ?? v.yukseltici
        eqAcik = try c.decodeIfPresent(Bool.self, forKey: .eqAcik) ?? v.eqAcik
        eqHazir = try c.decodeIfPresent(String.self, forKey: .eqHazir) ?? v.eqHazir
        eqOzel = try c.decodeIfPresent([Float].self, forKey: .eqOzel) ?? v.eqOzel
        if eqOzel.count != Ekolayzer.bantlar.count { eqOzel = v.eqOzel }
        otomatikGecis = try c.decodeIfPresent(Bool.self, forKey: .otomatikGecis) ?? v.otomatikGecis
        gecisModu = try c.decodeIfPresent(GecisModu.self, forKey: .gecisModu) ?? v.gecisModu
        kisSeviyesi = try c.decodeIfPresent(Float.self, forKey: .kisSeviyesi) ?? v.kisSeviyesi
        donusGecikmesi = try c.decodeIfPresent(Double.self, forKey: .donusGecikmesi) ?? v.donusGecikmesi
        gecisSuresi = try c.decodeIfPresent(Double.self, forKey: .gecisSuresi) ?? v.gecisSuresi
        medyaDuraklat = try c.decodeIfPresent(Bool.self, forKey: .medyaDuraklat) ?? v.medyaDuraklat
        pcSesiniKapat = try c.decodeIfPresent(Bool.self, forKey: .pcSesiniKapat) ?? v.pcSesiniKapat
        gecikme = try c.decodeIfPresent(GecikmeModu.self, forKey: .gecikme) ?? v.gecikme
        gorusmeKipi = try c.decodeIfPresent(Bool.self, forKey: .gorusmeKipi) ?? v.gorusmeKipi
        mikAcik = try c.decodeIfPresent(Bool.self, forKey: .mikAcik) ?? v.mikAcik
        mikYuksekKalite = try c.decodeIfPresent(Bool.self, forKey: .mikYuksekKalite) ?? v.mikYuksekKalite
        mikSesYalitimi = try c.decodeIfPresent(Bool.self, forKey: .mikSesYalitimi) ?? v.mikSesYalitimi
        otomatikBaglan = try c.decodeIfPresent(Bool.self, forKey: .otomatikBaglan) ?? v.otomatikBaglan
        sonPC = try c.decodeIfPresent(String.self, forKey: .sonPC)
        titresim = try c.decodeIfPresent(Bool.self, forKey: .titresim) ?? v.titresim
        genisAlgilama = try c.decodeIfPresent(Bool.self, forKey: .genisAlgilama) ?? v.genisAlgilama
        let eskiSurum = try c.decodeIfPresent(Int.self, forKey: .surum) ?? 1
        if eskiSurum < 2 {
            // 1.0'da varsayılan "Dengeli" idi; düşük gecikme varsayılan oldu.
            if gecikme == .dengeli { gecikme = .enDusuk }
        }
        surum = v.surum
    }

    /// PC panelinden gelen kısmi ayarları uygular (bilinmeyen anahtarlar yok sayılır).
    public func birlestir(_ kismi: Data) -> Ayarlar? {
        guard let kendi = try? JSONEncoder().encode(self),
              var mevcut = (try? JSONSerialization.jsonObject(with: kendi)) as? [String: Any],
              let ek = (try? JSONSerialization.jsonObject(with: kismi)) as? [String: Any] else { return nil }
        let bilinen = Set(mevcut.keys).union(["sonPC"])
        for (k, v) in ek where bilinen.contains(k) { mevcut[k] = v }
        guard let d = try? JSONSerialization.data(withJSONObject: mevcut) else { return nil }
        return try? JSONDecoder().decode(Ayarlar.self, from: d)
    }

    /// PC paneline gidecek JSON nesnesi.
    public func sozluk() -> [String: Any] {
        guard let d = try? JSONEncoder().encode(self), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        return o
    }

    /// Ekolayzerde şu an geçerli 10 bant kazancı (dB).
    public var eqKazanclari: [Float] {
        if eqHazir == "ozel" { return eqOzel }
        return Ekolayzer.hazir(eqHazir)?.kazanclar ?? Ekolayzer.hazirlar[0].kazanclar
    }
}

public struct EqHazir: Identifiable, Sendable {
    public let id: String
    public let ad: String
    public let kazanclar: [Float]
}

public enum Ekolayzer {
    /// Bant merkezleri (Hz) — klasik 10 bant.
    public static let bantlar: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let etiketler = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    public static let sinir: Float = 12

    public static let hazirlar: [EqHazir] = [
        EqHazir(id: "duz", ad: "Düz", kazanclar: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqHazir(id: "bas", ad: "Bas Güçlendirici", kazanclar: [6, 5, 4, 2.5, 1, 0, 0, 0, 0, 0]),
        EqHazir(id: "basAzalt", ad: "Bas Azaltıcı", kazanclar: [-6, -5, -4, -2.5, -1, 0, 0, 0, 0, 0]),
        EqHazir(id: "tiz", ad: "Tiz Güçlendirici", kazanclar: [0, 0, 0, 0, 0, 0.5, 1.5, 3, 4.5, 5.5]),
        EqHazir(id: "vokal", ad: "Vokal", kazanclar: [-2, -1.5, -1, 0.5, 2.5, 3.5, 3, 1.5, 0, -1]),
        EqHazir(id: "podcast", ad: "Konuşma", kazanclar: [-6, -4, -2, 0, 2, 3.5, 3.5, 2, 0, -2]),
        EqHazir(id: "film", ad: "Film", kazanclar: [4, 3, 1.5, 0, -0.5, 0, 1.5, 2.5, 2, 1]),
        EqHazir(id: "oyun", ad: "Oyun", kazanclar: [3, 2, 0, -1, -1, 0.5, 2, 3.5, 3, 1.5]),
        EqHazir(id: "elektronik", ad: "Elektronik", kazanclar: [5, 4, 1.5, 0, -1.5, 1, 0, 1.5, 4, 4.5]),
        EqHazir(id: "akustik", ad: "Akustik", kazanclar: [3, 2.5, 2, 1, 1, 1, 2, 2.5, 2, 1.5]),
        EqHazir(id: "rock", ad: "Rock", kazanclar: [4.5, 3.5, 2, 0.5, -0.5, -0.5, 0.5, 2, 3, 3.5]),
        EqHazir(id: "gece", ad: "Gece", kazanclar: [-3, -2, -1, 0, 1, 1.5, 1.5, 0.5, -1, -2]),
    ]

    public static func hazir(_ id: String) -> EqHazir? { hazirlar.first { $0.id == id } }

    /// Kırpılma olmasın diye en yüksek pozitif kazanç kadar ön kısma (dB).
    public static func onKisma(_ k: [Float]) -> Float {
        -max(0, k.max() ?? 0) * 0.7
    }
}
