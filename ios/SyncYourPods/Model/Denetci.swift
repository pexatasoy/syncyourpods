// Uygulamanın beyni: bağlantı, ses motoru, geçiş kuralı ve ayarları bir arada yürütür.
// Arayüz yalnız bunu gözler.

import AVFoundation
import Cekirdek
import Observation
import UIKit

enum BaglantiDurumu: Equatable {
    case araniyor
    case baglaniyor(String)
    case izinBekleniyor(String)
    case reddedildi(String)
    case bagli(String)

    var bagli: Bool { if case .bagli = self { return true }; return false }
}

enum Kaynak {
    case pc, telefon, sessiz, yok
}

struct Rota: Equatable {
    var ad = "Kulaklık bağlı değil"
    var simge = "headphones"
    var kulaklik = false
}

@MainActor
@Observable
final class Denetci {
    var ayarlar: Ayarlar {
        didSet { ayarlarDegisti(eski: oldValue) }
    }
    private(set) var durum = BaglantiDurumu.araniyor
    private(set) var bulunanlar: [BulunanPC] = []
    private(set) var pc: PCDurumu?
    private(set) var pcAdi: String?
    private(set) var telefonda = false
    private(set) var rota = Rota()
    private(set) var ist = TamponIstatistik()
    private(set) var seviye: Float = 0
    private(set) var rttMs: Double?
    private(set) var cikisGecikmesiMs: Double = 0
    /// PC'den gelen mikrofon durumu: "off" | "on" | "noDevice" | "error"
    private(set) var mikDurumu = "off"
    private(set) var ipucu = false
    private(set) var digerSes = false
    private(set) var sonHata: String?
    /// Dokunsal geri bildirim tetikleyicisi.
    private(set) var gecisSayaci = 0
    var mikIzniReddedildi = false
    /// DEBUG: ekran görüntüleri için sahte bağlı durum (-ornek YES).
    @ObservationIgnored private(set) var ornek = false

    @ObservationIgnored let motor = SesMotoru()
    @ObservationIgnored private let kesif = Kesif()
    @ObservationIgnored private var baglanti: Baglanti?
    @ObservationIgnored private let odak = OdakMotoru()
    @ObservationIgnored private var odakZamanlayici: Timer?
    @ObservationIgnored private var olcumZamanlayici: Timer?
    @ObservationIgnored private var yenidenDeneme: DispatchWorkItem?
    @ObservationIgnored private var kopmaAni: Date?
    @ObservationIgnored private var elleKesildi = false
    @ObservationIgnored private let telefonId: String

    init() {
        let d = UserDefaults.standard
        if let v = d.data(forKey: "ayarlar"), let a = try? JSONDecoder().decode(Ayarlar.self, from: v) {
            ayarlar = a
        } else {
            ayarlar = Ayarlar()
        }
        if let id = d.string(forKey: "telefonId") {
            telefonId = id
        } else {
            telefonId = UUID().uuidString
            d.set(telefonId, forKey: "telefonId")
        }
        // Mikrofon her açılışta kapalı başlar: kalite düşüşü sürpriz olmasın.
        ayarlar.mikAcik = false
        odakAyarla()
        motor.uygula(ayarlar)
        rota = Self.rotaOku()
        motor.kulaklikYok = !rota.kulaklik

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ornek") {
            ornekDoldur()
            return
        }
        #endif

        kesif.degisti = { [weak self] liste in self?.bulunanlarDegisti(liste) }
        kesif.baslat()

        let m = NotificationCenter.default
        m.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rotaDegisti() }
        }
        m.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let tur = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                if tur == .ended { self?.motor.surdur() }
            }
        }
        m.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.motoruBaslat() }
        }
        m.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.odakKontrol() }
        }

        // Geçiş kuralı arka planda da işler (motor çalıştığı sürece uygulama uyanık).
        odakZamanlayici = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.odakKontrol() }
        }
    }

    // MARK: Görünen durum

    var kaynak: Kaynak {
        guard durum.bagli else { return .yok }
        if telefonda { return .telefon }
        return (pc?.playing ?? false) ? .pc : .sessiz
    }

    var durumMetni: String {
        switch durum {
        case .araniyor: return bulunanlar.isEmpty ? "Bilgisayar aranıyor" : "Bağlanmak için bilgisayar seç"
        case let .baglaniyor(ad): return "\(ad) bağlanıyor"
        case let .izinBekleniyor(ad): return "\(ad) üzerinde izin ver"
        case let .reddedildi(ad): return "\(ad) izin vermedi"
        case .bagli:
            if !rota.kulaklik { return "AirPods’u tak" }
            switch kaynak {
            case .pc: return "Bilgisayardan çalıyor"
            case .telefon: return "iPhone’dan çalıyor"
            case .sessiz: return "Bilgisayar sessiz"
            case .yok: return ""
            }
        }
    }

    /// Bluetooth dahil toplam gecikme tahmini (ms).
    var toplamGecikmeMs: Double {
        ist.tamponMs + cikisGecikmesiMs + (rttMs ?? 4) / 2
    }

    // MARK: Bağlantı

    private func bulunanlarDegisti(_ liste: [BulunanPC]) {
        bulunanlar = liste
        otomatikBaglan()
    }

    private func otomatikBaglan() {
        guard baglanti == nil, ayarlar.otomatikBaglan, !elleKesildi else { return }
        if let son = ayarlar.sonPC, let pc = bulunanlar.first(where: { $0.id == son }) {
            baglan(pc)
        } else if bulunanlar.count == 1, ayarlar.sonPC == nil {
            baglan(bulunanlar[0])
        }
    }

    func baglan(_ pc: BulunanPC) {
        elleKesildi = false
        yenidenDeneme?.cancel()
        baglanti?.olay = nil
        baglanti?.kapat()
        motor.sifirla()
        let b = Baglanti(pc: pc)
        let motor = self.motor
        b.sesPaketi = { veri in
            motor.paketAl(veri, simdi: Double(DispatchTime.now().uptimeNanoseconds) / 1e9)
        }
        motor.mikrofonCikisi = { [weak b] ornek, hiz in b?.mikrofonGonder(ornek, hiz: hiz) }
        b.olay = { [weak self, weak b] o in
            guard let self, let b, self.baglanti === b else { return }
            self.olay(o, pc: pc)
        }
        baglanti = b
        pcAdi = pc.ad
        durum = .baglaniyor(pc.ad)
        if !motor.motorCalisiyor { motoruBaslat() }
        b.baslat(telefonId: telefonId, telefonAdi: UIDevice.current.name)
    }

    func kes() {
        elleKesildi = true
        yenidenDeneme?.cancel()
        baglanti?.olay = nil
        baglanti?.kapat()
        baglanti = nil
        pc = nil
        telefondaAyarla(false)
        durum = .araniyor
        motor.durdur()
    }

    private func olay(_ o: BaglantiOlayi, pc bulunan: BulunanPC) {
        switch o {
        case .hazir:
            break
        case let .mesaj(m):
            switch m {
            case let .welcome(ad, id, _):
                durum = .bagli(ad)
                pcAdi = ad
                sonHata = nil
                kopmaAni = nil
                if ayarlar.sonPC != id && ayarlar.sonPC != bulunan.id { ayarlar.sonPC = bulunan.id }
                baglanti?.gonder(.settings(pauseMedia: ayarlar.medyaDuraklat, muteLocal: ayarlar.pcSesiniKapat))
                if telefonda { baglanti?.gonder(.focus(phone: true)) }
                if ayarlar.mikAcik { baglanti?.gonder(.mic(on: true)) }
            case .wait:
                durum = .izinBekleniyor(bulunan.ad)
            case .denied:
                durum = .reddedildi(bulunan.ad)
                elleKesildi = true
            case let .status(d):
                pc = d
                // PC'nin tepsi menüsünden değiştirildiyse buraya da yansısın.
                if d.pauseMedia != ayarlar.medyaDuraklat { ayarlar.medyaDuraklat = d.pauseMedia }
                if let m = d.muteLocal, m != ayarlar.pcSesiniKapat { ayarlar.pcSesiniKapat = m }
            case let .micState(s):
                mikDurumu = s
                if s == "noDevice" || s == "error", ayarlar.mikAcik {
                    ayarlar.mikAcik = false
                }
            default:
                break
            }
        case let .koptu(neden):
            baglanti = nil
            pc = nil
            mikDurumu = "off"
            if case .reddedildi = durum { return }
            sonHata = neden
            durum = .araniyor
            motor.sifirla()
            if kopmaAni == nil { kopmaAni = Date() }
            // 2 dakika boyunca yeniden dene; sonra motoru durdur (pil).
            if let k = kopmaAni, Date().timeIntervalSince(k) > 120 {
                motor.durdur()
                return
            }
            let is_ = DispatchWorkItem { [weak self] in
                guard let self, self.baglanti == nil else { return }
                if let p = self.bulunanlar.first(where: { $0.id == bulunan.id }) ?? self.bulunanlar.first(where: { $0.ad == bulunan.ad }) {
                    self.baglan(p)
                } else {
                    self.otomatikBaglan()
                }
            }
            yenidenDeneme = is_
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: is_)
        }
    }

    /// Uygulama öne gelince: kesif tazelensin, motor durduysa ve bağlantı yoksa yeniden dene.
    func oneGeldi() {
        guard !ornek else { return }
        kesif.baslat()
        if baglanti == nil, !elleKesildi {
            kopmaAni = nil
            otomatikBaglan()
        }
        olcumBaslat()
    }

    func arkayaGitti() {
        olcumZamanlayici?.invalidate()
        olcumZamanlayici = nil
    }

    // MARK: Ses

    private func motoruBaslat() {
        do {
            try motor.baslat(mikrofon: ayarlar.mikAcik, yuksekKalite: ayarlar.mikYuksekKalite, yalitim: ayarlar.mikSesYalitimi,
                             gorusme: ayarlar.gorusmeKipi)
            sonHata = nil
        } catch {
            sonHata = "Ses başlatılamadı: \(error.localizedDescription)"
        }
        rotaDegisti()
    }

    private func rotaDegisti() {
        rota = Self.rotaOku()
        motor.kulaklikYok = !rota.kulaklik
        cikisGecikmesiMs = motor.cikisGecikmesiMs
    }

    static func rotaOku() -> Rota {
        guard let o = AVAudioSession.sharedInstance().currentRoute.outputs.first else { return Rota() }
        let ad = o.portName
        let k = ad.lowercased()
        switch o.portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            let simge: String
            if k.contains("max") { simge = "airpodsmax" }
            else if k.contains("pro") { simge = "airpodspro" }
            else if k.contains("airpods") { simge = "airpods" }
            else { simge = "headphones" }
            return Rota(ad: ad, simge: simge, kulaklik: true)
        case .headphones, .usbAudio, .airPlay, .carAudio, .HDMI, .lineOut:
            return Rota(ad: ad, simge: "headphones", kulaklik: true)
        default:
            return Rota(ad: "Kulaklık bağlı değil", simge: "headphones", kulaklik: false)
        }
    }

    // MARK: Geçiş kuralı

    private func odakAyarla() {
        odak.otomatik = ayarlar.otomatikGecis
        odak.mod = ayarlar.gecisModu
        odak.kisSeviyesi = ayarlar.kisSeviyesi
        odak.donusGecikmesi = ayarlar.donusGecikmesi
    }

    private func odakKontrol() {
        guard !ornek else { return }
        let o = AVAudioSession.sharedInstance()
        ipucu = o.secondaryAudioShouldBeSilencedHint
        digerSes = o.isOtherAudioPlaying
        let caliyor = ayarlar.genisAlgilama ? (ipucu || digerSes) : ipucu
        if let ol = odak.guncelle(digerSesCaliyor: caliyor, simdi: Date().timeIntervalSinceReferenceDate) {
            telefondaAyarla(ol == .telefonaGecti)
        } else {
            motor.odakKazanci(odak.pcKazanci)
        }
    }

    private func telefondaAyarla(_ t: Bool) {
        guard telefonda != t else { return }
        telefonda = t
        motor.odakKazanci(odak.pcKazanci)
        if durum.bagli {
            baglanti?.gonder(.focus(phone: t))
            gecisSayaci += 1
        }
    }

    // MARK: Ölçüm (yalnız ekran açıkken)

    func olcumBaslat() {
        guard olcumZamanlayici == nil, !ornek else { return }
        olcumZamanlayici = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.olc() }
        }
    }

    private var olcumAdim = 0
    private func olc() {
        let (i, s) = motor.olcum()
        seviye = s
        olcumAdim += 1
        // İstatistikler saniyede 3 kez yeter.
        if olcumAdim % 5 == 0 {
            ist = i
            rttMs = baglanti?.rttMs
            cikisGecikmesiMs = motor.cikisGecikmesiMs
        }
    }

    // MARK: Ayarlar

    private func ayarlarDegisti(eski: Ayarlar) {
        if let v = try? JSONEncoder().encode(ayarlar) {
            UserDefaults.standard.set(v, forKey: "ayarlar")
        }
        motor.uygula(ayarlar)
        odakAyarla()
        if eski.medyaDuraklat != ayarlar.medyaDuraklat || eski.pcSesiniKapat != ayarlar.pcSesiniKapat {
            baglanti?.gonder(.settings(pauseMedia: ayarlar.medyaDuraklat, muteLocal: ayarlar.pcSesiniKapat))
        }
        if eski.gorusmeKipi != ayarlar.gorusmeKipi, !ayarlar.mikAcik, motor.motorCalisiyor {
            motoruBaslat()
        }
        let mikDegisti = eski.mikAcik != ayarlar.mikAcik
            || (ayarlar.mikAcik && (eski.mikYuksekKalite != ayarlar.mikYuksekKalite || eski.mikSesYalitimi != ayarlar.mikSesYalitimi))
        if mikDegisti {
            if ayarlar.mikAcik && !eski.mikAcik {
                mikrofonIzni()
            } else {
                mikrofonUygula()
            }
        }
    }

    private func mikrofonIzni() {
        AVAudioApplication.requestRecordPermission { izin in
            DispatchQueue.main.async {
                if izin {
                    self.mikIzniReddedildi = false
                    self.mikrofonUygula()
                } else {
                    self.mikIzniReddedildi = true
                    self.ayarlar.mikAcik = false
                }
            }
        }
    }

    private func mikrofonUygula() {
        if motor.motorCalisiyor || baglanti != nil { motoruBaslat() }
        baglanti?.gonder(.mic(on: ayarlar.mikAcik))
        if !ayarlar.mikAcik { mikDurumu = "off" }
    }

    #if DEBUG
    private func ornekDoldur() {
        ornek = true
        let u = UserDefaults.standard
        durum = .bagli("EFE-PC")
        pcAdi = "EFE-PC"
        bulunanlar = [BulunanPC(id: "ornek", ad: "EFE-PC", uc: .hostPort(host: "192.168.1.20", port: 47800))]
        pc = PCDurumu(playing: true, device: "Hoparlör (Realtek Audio)", title: "lofi hip hop radio – beats to relax/study to",
                      artist: "Lofi Girl", app: "Chrome", pauseMedia: true)
        rota = Rota(ad: "Efe’nin AirPods Pro’su", simge: "airpodspro", kulaklik: true)
        telefonda = u.bool(forKey: "telefonda")
        var i = TamponIstatistik()
        i.alinan = 18234; i.kurtarilan = 41; i.kayip = 2; i.gec = 3
        i.tamponMs = 34; i.hedefMs = 35; i.titremeMs = 6.2; i.kaymaPpm = 41; i.durum = .caliyor
        ist = i
        seviye = 0.45
        rttMs = 4
        cikisGecikmesiMs = 162
        if u.bool(forKey: "ozelEq") {
            ayarlar.eqAcik = true
            ayarlar.eqHazir = "ozel"
            ayarlar.eqOzel = [4, 3, 1, 0, -1, 0, 1.5, 3, 2, 1]
        } else if u.string(forKey: "ekran") == "ekolayzer" {
            ayarlar.eqAcik = true
            ayarlar.eqHazir = "bas"
        }
    }
    #endif
}
