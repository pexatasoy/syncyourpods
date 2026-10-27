// Titreşim tamponu: ağdan sırası karışık/eksik gelen paketleri düzgün, kesintisiz bir sese çevirir.
//
// - Paketler sıra numarasına göre yuvalara yazılır; yedekli paket bir öncekini kurtarır.
// - Çalma noktası hedef doluluğa (ms) ulaşınca başlar. Hedef ağın titreşimine göre kendini ayarlar,
//   gecikme modunun taban/tavan sınırları içinde kalır.
// - PC'nin ve iPhone'un saatleri birebir aynı değil: doluluk hedeften saparsa okuma hızı binde birkaç
//   oynatılır (duyulmaz), tampon ne şişer ne boşalır. Çok şişerse (ağ takılıp topluca gelirse) fazlası atılır.
// - Kayıp parça önceki parçanın sönümlenmesiyle örtülür; ardından gelen parça yumuşak açılır.
//
// ⚠️ İş parçacığı güvenli DEĞİL: iOS tarafı tek kilitle sarar (ağ ve ses iş parçacığı).
// ⚠️ `oku` ses iş parçacığında çağrılır: içinde bellek ayırma YOK, her şey önceden ayrılmış.

import Foundation

public enum GecikmeModu: String, Codable, CaseIterable, Sendable {
    case enDusuk, dengeli, kararli

    /// Tamponun en az tutacağı ses (ms).
    public var taban: Double { switch self { case .enDusuk: 15; case .dengeli: 35; case .kararli: 80 } }
    /// Ağ ne kadar kötü olursa olsun tamponun çıkabileceği en üst sınır (ms).
    public var tavan: Double { switch self { case .enDusuk: 60; case .dengeli: 120; case .kararli: 250 } }
}

public enum TamponDurumu: String, Sendable {
    case bos, doluyor, caliyor
}

public struct TamponIstatistik: Sendable, Equatable {
    public var alinan = 0
    public var kurtarilan = 0
    public var kayip = 0
    public var gec = 0
    public var bosalma = 0
    public var atlama = 0
    public var tamponMs = 0.0
    public var hedefMs = 0.0
    public var titremeMs = 0.0
    public var kaymaPpm = 0.0
    public var girisHizi = 48000.0
    public var durum = TamponDurumu.bos
    public init() {}
}

public final class SesTamponu {
    public let cikisHizi: Double
    public var mod: GecikmeModu { didSet { hedefiGuncelle() } }
    public private(set) var ist = TamponIstatistik()

    private let kare = Protokol.kare
    private let yuvaSayisi = 256 // ≈ 850 ms
    private var yuvalar: [Float]
    private var yuvaSira: [UInt32]
    private var yuvaDolu: [Bool]

    // Sıralı, çalınmayı bekleyen kareler (araya girmiş stereo) — halka.
    private let akisKapasite: Int
    private var akis: [Float]
    private var akisBas = 0 // okuma başı (kare)
    private var akisSay = 0 // içindeki kare
    private var konum = 0.0 // akisBas'tan itibaren kesirli okuma konumu

    private var sonraki: UInt32 = 0
    private var enYeni: UInt32 = 0
    private var akisVar = false
    private var bosta = true
    private var durum = TamponDurumu.bos

    private var sonParca: [Float]
    private var sonParcaVar = false
    private var yumusakAc = false

    private var girisHizi = 48000.0
    private var hedefKare = 0.0
    private var dolulukOrt = 0.0
    private var ayar = 0.0
    private var titreme = 0.0 // sn
    private var zamanTaban = Double.greatestFiniteMagnitude

    public init(cikisHizi: Double = 48000, mod: GecikmeModu = .dengeli) {
        self.cikisHizi = cikisHizi
        self.mod = mod
        yuvalar = [Float](repeating: 0, count: yuvaSayisi * Protokol.kare * 2)
        yuvaSira = [UInt32](repeating: 0, count: yuvaSayisi)
        yuvaDolu = [Bool](repeating: false, count: yuvaSayisi)
        akisKapasite = Int(cikisHizi) * 2 // 2 sn
        akis = [Float](repeating: 0, count: akisKapasite * 2)
        sonParca = [Float](repeating: 0, count: Protokol.kare * 2)
        hedefiGuncelle()
    }

    /// Bağlantı yenilenince / oturum değişince.
    public func sifirla() {
        for i in 0..<yuvaSayisi { yuvaDolu[i] = false }
        akisBas = 0; akisSay = 0; konum = 0
        akisVar = false; bosta = true; durum = .bos
        sonParcaVar = false; yumusakAc = false
        dolulukOrt = 0; ayar = 0; titreme = 0
        zamanTaban = .greatestFiniteMagnitude
        hedefiGuncelle()
        ist.durum = .bos
    }

    // MARK: Ağdan gelen

    /// `simdi`: saniye cinsinden tekdüze saat (titreşim ölçümü için).
    public func al(_ p: UnsafeRawBufferPointer, simdi: Double) {
        guard let b = Baslik.oku(p) else { return }
        switch b.tur {
        case .sessizlik:
            bosta = true
        case .ses:
            guard b.kanal == 2, b.bicim == Protokol.bicimS16, Int(b.kare) == kare else { return }
            let parca = kare * 2 * 2
            guard p.count >= Protokol.baslik + parca else { return }
            ist.alinan += 1
            bosta = false
            if Double(b.hiz) != girisHizi {
                girisHizi = Double(b.hiz)
                sifirla()
            }
            if !akisVar || durum == .bos {
                yenidenBasla(b.sira)
            }
            let ileri = Int32(bitPattern: b.sira &- sonraki)
            if ileri < 0 {
                ist.gec += 1
                return
            }
            if Int(ileri) >= yuvaSayisi {
                // Uzun kopukluk ya da PC yeniden başladı: baştan.
                yenidenBasla(b.sira)
            }
            yaz(sira: b.sira, kaynak: p, bayt: Protokol.baslik)
            if b.bayrak & Protokol.yedekVar != 0, p.count >= Protokol.baslik + parca * 2 {
                let onceki = b.sira &- 1
                if Int32(bitPattern: onceki &- sonraki) >= 0, !doluMu(onceki) {
                    yaz(sira: onceki, kaynak: p, bayt: Protokol.baslik + parca)
                    ist.kurtarilan += 1
                }
            }
            if Int32(bitPattern: b.sira &- enYeni) > 0 { enYeni = b.sira }
            titremeOlc(konum: b.konum, simdi: simdi)
        default:
            return
        }
    }

    private func yenidenBasla(_ sira: UInt32) {
        for i in 0..<yuvaSayisi { yuvaDolu[i] = false }
        akisBas = 0; akisSay = 0; konum = 0
        sonraki = sira; enYeni = sira
        akisVar = true
        durum = .doluyor
        sonParcaVar = false
        yumusakAc = true
        dolulukOrt = hedefKare
        zamanTaban = .greatestFiniteMagnitude
    }

    private func doluMu(_ sira: UInt32) -> Bool {
        let y = Int(sira % UInt32(yuvaSayisi))
        return yuvaDolu[y] && yuvaSira[y] == sira
    }

    private func yaz(sira: UInt32, kaynak p: UnsafeRawBufferPointer, bayt: Int) {
        let y = Int(sira % UInt32(yuvaSayisi))
        let n = kare * 2
        let taban = y * n
        for i in 0..<n {
            let lo = UInt16(p[bayt + i * 2]), hi = UInt16(p[bayt + i * 2 + 1])
            yuvalar[taban + i] = Float(Int16(bitPattern: lo | hi << 8)) / 32768
        }
        yuvaSira[y] = sira
        yuvaDolu[y] = true
    }

    private func titremeOlc(konum: UInt32, simdi: Double) {
        // Her paket "konum/hız" anında yola çıkmış sayılır; geliş bundan ne kadar geç → titreşim.
        let fark = simdi - Double(konum) / girisHizi
        zamanTaban = min(zamanTaban + 0.000001, fark)
        let gecikme = fark - zamanTaban
        titreme = max(gecikme, titreme * 0.9995)
        hedefiGuncelle()
    }

    private func hedefiGuncelle() {
        let ms = min(mod.tavan, max(mod.taban, titreme * 1000 * 1.2 + 6))
        hedefKare = ms / 1000 * cikisHizi
        ist.hedefMs = ms
        ist.titremeMs = titreme * 1000
    }

    // MARK: Ses iş parçacığı

    /// `n` kare üretir. Ses yoksa sıfır yazar.
    public func oku(_ n: Int, sol: UnsafeMutablePointer<Float>, sag: UnsafeMutablePointer<Float>) {
        if durum == .bos || !akisVar {
            sifirYaz(n, sol, sag, from: 0)
            ist.durum = .bos
            return
        }
        let oran = girisHizi / cikisHizi
        let bekleyen = bekleyenParca()
        let doluluk = Double(akisSay + bekleyen * kare) / oran - konum / oran
        if durum == .doluyor {
            if doluluk >= hedefKare || (bosta && bekleyen > 0) {
                durum = .caliyor
            } else {
                sifirYaz(n, sol, sag, from: 0)
                istGuncelle(doluluk)
                return
            }
        }

        // Saat kayması denetimi. Atlama, okumadan ÖNCE: o an çalınacak sesi atmasın.
        dolulukOrt = dolulukOrt * 0.98 + doluluk * 0.02
        let hata = (dolulukOrt - hedefKare) / max(hedefKare, 1)
        ayar = max(-0.003, min(0.003, hata * 0.004))
        if doluluk > hedefKare * 2.5 + cikisHizi * 0.02 {
            atla(hedef: max(hedefKare, Double(n) * 2))
        }
        let adim = oran * (1 + ayar)
        let gereken = Int((Double(n) * adim + konum).rounded(.up)) + 2
        doldur(gereken)

        var i = 0
        while i < n {
            let k = Int(konum)
            if k + 1 >= akisSay { break }
            let f = Float(konum - Double(k))
            let a = ((akisBas + k) % akisKapasite) * 2
            let b = ((akisBas + k + 1) % akisKapasite) * 2
            sol[i] = akis[a] + (akis[b] - akis[a]) * f
            sag[i] = akis[a + 1] + (akis[b + 1] - akis[a + 1]) * f
            konum += adim
            i += 1
        }
        let tuketilen = min(Int(konum), akisSay)
        akisBas = (akisBas + tuketilen) % akisKapasite
        akisSay -= tuketilen
        konum -= Double(tuketilen)

        if i < n {
            // Boşalma: elimizdekinin sonunu kısa sön, kalanı sessiz.
            let sonum = min(i, 48)
            for j in 0..<sonum {
                let g = Float(sonum - j) / Float(sonum + 1)
                sol[i - sonum + j] *= g
                sag[i - sonum + j] *= g
            }
            sifirYaz(n, sol, sag, from: i)
            if !bosta {
                ist.bosalma += 1
                titreme = min(mod.tavan / 1000, titreme + 0.010)
                hedefiGuncelle()
            }
            durum = bosta ? .bos : .doluyor
            if durum == .bos { akisVar = false }
        }
        istGuncelle(doluluk)
    }

    private func bekleyenParca() -> Int {
        let ileri = Int(Int32(bitPattern: enYeni &- sonraki))
        guard ileri >= 0 else { return 0 }
        var say = 0
        var s = sonraki
        for _ in 0...min(ileri, yuvaSayisi - 1) {
            if doluMu(s) { say += 1 }
            s &+= 1
        }
        return say
    }

    /// Akışı en az `gereken` kareye tamamlar: sıradaki yuvayı alır, kayıpsa örter.
    private func doldur(_ gereken: Int) {
        while akisSay < gereken, akisSay + kare <= akisKapasite {
            if doluMu(sonraki) {
                let y = Int(sonraki % UInt32(yuvaSayisi))
                ekleAkisa(yuva: y)
                yuvaDolu[y] = false
                sonraki &+= 1
            } else if Int32(bitPattern: enYeni &- sonraki) > 0 {
                ist.kayip += 1
                ortbas()
                sonraki &+= 1
            } else {
                return
            }
        }
    }

    private func ekleAkisa(yuva y: Int) {
        let n = kare * 2
        let taban = y * n
        var yaz = ((akisBas + akisSay) % akisKapasite) * 2
        for j in 0..<kare {
            var l = yuvalar[taban + j * 2], r = yuvalar[taban + j * 2 + 1]
            if yumusakAc, j < 64 {
                let g = Float(j) / 64
                l *= g; r *= g
            }
            akis[yaz] = l; akis[yaz + 1] = r
            sonParca[j * 2] = l; sonParca[j * 2 + 1] = r
            yaz = (yaz + 2) % (akisKapasite * 2)
        }
        yumusakAc = false
        sonParcaVar = true
        akisSay += kare
    }

    /// Kayıp parça: son parça sönerek tekrar edilir; art arda kayıpta sessizlik.
    private func ortbas() {
        var yaz = ((akisBas + akisSay) % akisKapasite) * 2
        for j in 0..<kare {
            let g: Float = sonParcaVar ? Float(kare - j) / Float(kare) : 0
            akis[yaz] = sonParca[j * 2] * g
            akis[yaz + 1] = sonParca[j * 2 + 1] * g
            yaz = (yaz + 2) % (akisKapasite * 2)
        }
        sonParcaVar = false
        yumusakAc = true
        akisSay += kare
    }

    /// Tampon çok şişti: fazlasını at, gecikme hemen hedefe insin.
    private func atla(hedef: Double) {
        let oran = girisHizi / cikisHizi
        var fazla = Int((Double(akisSay + bekleyenParca() * kare) - hedef * oran))
        while fazla >= kare, Int32(bitPattern: enYeni &- sonraki) > 0 {
            let y = Int(sonraki % UInt32(yuvaSayisi))
            if doluMu(sonraki) { yuvaDolu[y] = false }
            sonraki &+= 1
            fazla -= kare
        }
        if fazla > 0 {
            let at = min(fazla, max(0, akisSay - 2))
            akisBas = (akisBas + at) % akisKapasite
            akisSay -= at
        }
        yumusakAc = true
        dolulukOrt = hedef
        ist.atlama += 1
    }

    private func sifirYaz(_ n: Int, _ sol: UnsafeMutablePointer<Float>, _ sag: UnsafeMutablePointer<Float>, from: Int) {
        guard from < n else { return }
        for i in from..<n { sol[i] = 0; sag[i] = 0 }
    }

    private func istGuncelle(_ doluluk: Double) {
        ist.tamponMs = doluluk / cikisHizi * 1000
        ist.kaymaPpm = ayar * 1_000_000
        ist.girisHizi = girisHizi
        ist.durum = durum
    }
}
