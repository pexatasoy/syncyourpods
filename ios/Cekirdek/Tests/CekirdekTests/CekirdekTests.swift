import XCTest
@testable import Cekirdek

final class PaketTestleri: XCTestCase {
    func testAltinBaslik() {
        // Rust'taki `altin_baslik` ile aynı baytlar.
        let b = Baslik(tur: .ses, bayrak: 1, oturum: 0x01020304, sira: 7, konum: 1120, kare: 160, kanal: 2, bicim: 1, hiz: 48000)
        var v = [UInt8]()
        b.yaz(&v)
        XCTAssertEqual(v.map { String(format: "%02x", $0) }.joined(), "53010100040302010700000060040000a000020180bb0000")
        XCTAssertEqual(Baslik.oku(v), b)
    }

    func testMesajlar() {
        let s = String(decoding: Mesaj.settings(pauseMedia: true, muteLocal: false).satir(), as: UTF8.self)
        XCTAssertEqual(s, "{\"muteLocal\":false,\"pauseMedia\":true,\"t\":\"settings\"}\n")
        let w = Mesaj.coz(Data("{\"t\":\"welcome\",\"v\":1,\"pc\":\"EFE-PC\",\"id\":\"ab\",\"session\":4093603538,\"udp\":47800}".utf8))
        XCTAssertEqual(w, .welcome(pc: "EFE-PC", id: "ab", session: 4093603538))
        let st = Mesaj.coz(Data("{\"t\":\"status\",\"playing\":true,\"device\":\"Hoparlör\",\"title\":\"Lofi\",\"artist\":null,\"app\":\"Chrome\",\"pauseMedia\":false,\"muteLocal\":true}".utf8))
        XCTAssertEqual(st, .status(PCDurumu(playing: true, device: "Hoparlör", title: "Lofi", artist: nil, app: "Chrome", pauseMedia: false, muteLocal: true)))
        XCTAssertEqual(Mesaj.coz(Data("{\"t\":\"micstate\",\"state\":\"noDevice\"}".utf8)), .micState("noDevice"))
    }

    func testMikrofonPaketi() {
        let o: [Float] = [0, 0.5, -1]
        let p = o.withUnsafeBufferPointer { mikrofonPaketi(oturum: 5, sira: 2, konum: 320, hiz: 24000, ornekler: $0) }
        let b = Baslik.oku(p)!
        XCTAssertEqual(b.tur, .mikrofon)
        XCTAssertEqual(b.kanal, 1)
        XCTAssertEqual(b.hiz, 24000)
        XCTAssertEqual(p.count, 24 + 6)
    }
}

/// PC'nin paketleyicisini taklit eder: 160 karelik parçalar, bir öncekini yedek taşır.
struct SahtePC {
    var sira: UInt32 = 0
    var konum: UInt32 = 0
    var onceki: [UInt8]?
    let hiz: UInt32 = 48000

    mutating func paket(_ deger: (Int) -> Int16) -> [UInt8] {
        var yuk = [UInt8]()
        for i in 0..<160 {
            let v = deger(Int(konum) + i)
            for _ in 0..<2 { yuk.append(UInt8(truncatingIfNeeded: v)); yuk.append(UInt8(truncatingIfNeeded: v >> 8)) }
        }
        var b = [UInt8]()
        Baslik(tur: .ses, bayrak: onceki == nil ? 0 : 1, oturum: 1, sira: sira, konum: konum, kare: 160, kanal: 2, hiz: hiz).yaz(&b)
        b += yuk
        if let o = onceki { b += o }
        onceki = yuk
        sira &+= 1
        konum &+= 160
        return b
    }

    func sessizlik() -> [UInt8] {
        var b = [UInt8]()
        Baslik(tur: .sessizlik, oturum: 1, sira: sira, konum: konum, kare: 0, kanal: 2, hiz: hiz).yaz(&b)
        return b
    }
}

final class TamponTestleri: XCTestCase {
    func ver(_ t: SesTamponu, _ p: [UInt8], _ simdi: Double) {
        p.withUnsafeBytes { t.al($0, simdi: simdi) }
    }

    func cek(_ t: SesTamponu, _ n: Int) -> [Float] {
        var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in t.oku(n, sol: lp.baseAddress!, sag: rp.baseAddress!) } }
        return l
    }

    /// Düzenli akış: önce dolar, sonra kesintisiz çalar, gecikme hedef civarında kalır.
    func testDuzenliAkis() {
        let t = SesTamponu(cikisHizi: 48000, mod: .dengeli)
        var pc = SahtePC()
        var simdi = 0.0
        var cikti = [Float]()
        // 2 sn: her 160 karede bir paket, her 240 karede bir okuma (iOS 5 ms).
        var uretilen = 0, okunan = 0
        while uretilen < 96000 {
            if uretilen <= okunan + 2000 || okunan >= uretilen {
                ver(t, pc.paket { Int16(($0 % 100) * 100) }, simdi)
                uretilen += 160
                simdi += 160.0 / 48000
            }
            if Double(okunan) < simdi * 48000 - 0 {
                cikti += cek(t, 240)
                okunan += 240
            }
        }
        XCTAssertEqual(t.ist.bosalma, 0)
        XCTAssertEqual(t.ist.kayip, 0)
        XCTAssertEqual(t.ist.durum, .caliyor)
        XCTAssertLessThan(abs(t.ist.tamponMs - t.ist.hedefMs), 25, "doluluk hedefe yakın olmalı: \(t.ist)")
        XCTAssertGreaterThan(cikti.filter { $0 != 0 }.count, cikti.count / 2)
    }

    /// Tek kayıp yedekten kurtarılır; iki ardışık kayıpta biri örtülür.
    func testKayipVeYedek() {
        let t = SesTamponu(cikisHizi: 48000, mod: .enDusuk)
        var pc = SahtePC()
        var paketler = (0..<40).map { _ in pc.paket { _ in 1000 } }
        paketler.remove(at: 10)            // tek kayıp → 11'in yedeğinden döner
        paketler.removeSubrange(20...21)   // 21,22 kayıp (indeks kaydı) → biri 23'ün yedeğinden döner, biri örtülür
        // Gerçek zamanlı gibi: her paketin ardından bir paketlik okuma.
        for p in paketler {
            let sira = Baslik.oku(p)!.sira
            ver(t, p, Double(sira) * 160 / 48000)
            _ = cek(t, 160)
        }
        for _ in 0..<10 { _ = cek(t, 160) }
        XCTAssertEqual(t.ist.atlama, 0)
        XCTAssertEqual(t.ist.kurtarilan, 2)
        XCTAssertEqual(t.ist.kayip, 1)
    }

    /// Sessizlik paketi bitişi boşalma sayılmaz; ses dönünce yeniden dolar.
    func testSessizlik() {
        let t = SesTamponu(cikisHizi: 48000, mod: .enDusuk)
        var pc = SahtePC()
        var simdi = 0.0
        for _ in 0..<20 { ver(t, pc.paket { _ in 500 }, simdi); simdi += 0.0033 }
        ver(t, pc.sessizlik(), simdi)
        for _ in 0..<40 { _ = cek(t, 240) }
        XCTAssertEqual(t.ist.durum, .bos)
        XCTAssertEqual(t.ist.bosalma, 0)
        for _ in 0..<20 { ver(t, pc.paket { _ in 500 }, simdi); simdi += 0.0033 }
        _ = cek(t, 240)
        XCTAssertEqual(t.ist.durum, .caliyor)
    }

    /// Ağ takılıp paketler topluca gelirse fazlası atılır, gecikme şişmez.
    func testSismeAtilir() {
        let t = SesTamponu(cikisHizi: 48000, mod: .enDusuk)
        var pc = SahtePC()
        for _ in 0..<200 { ver(t, pc.paket { _ in 700 }, 0) }
        for _ in 0..<5 { _ = cek(t, 240) }
        XCTAssertGreaterThan(t.ist.atlama, 0)
        XCTAssertLessThan(t.ist.tamponMs, 100)
    }

    /// Ekran kilitlenince iOS 1024 karelik bloklarla ister: tampon buna uyar, sürekli boşalmaz.
    func testBuyukBlok() {
        let t = SesTamponu(cikisHizi: 48000, mod: .enDusuk)
        var pc = SahtePC()
        var uret = 0.0, oku = 0.0
        for _ in 0..<6000 {
            if uret <= oku + 0.06 { ver(t, pc.paket { _ in 900 }, uret); uret += 160 / 48000.0 }
            if oku < uret - 0.04 { _ = cek(t, 1024); oku += 1024 / 48000.0 }
        }
        XCTAssertLessThanOrEqual(t.ist.bosalma, 1, "\(t.ist)")
        XCTAssertGreaterThan(t.ist.hedefMs, 1024 / 48.0)
    }

    /// Wi-Fi 80 ms takılıp paketleri topluca verir: ses ATILMAZ (hece yutulmaz).
    func testTopluGelisAtlamaz() {
        let t = SesTamponu(cikisHizi: 48000, mod: .enDusuk)
        var pc = SahtePC()
        var zaman = 0.0, oku = 0.0
        var bekleyenler: [[UInt8]] = []
        for adim in 0..<3000 {
            let p = pc.paket { _ in 800 }
            zaman += 160 / 48000.0
            // her 2 sn'de bir 80 ms takılma
            let takili = (adim % 600) >= 576
            if takili { bekleyenler.append(p) } else {
                for b in bekleyenler { ver(t, b, zaman) }
                bekleyenler.removeAll()
                ver(t, p, zaman)
            }
            while oku < zaman - 0.02 { _ = cek(t, 240); oku += 240 / 48000.0 }
        }
        XCTAssertEqual(t.ist.atlama, 0, "\(t.ist)")
    }

    /// Kübik ara değerleme doğruyu birebir verir.
    func testKubik() {
        XCTAssertEqual(SesTamponu.kubik(0, 1, 2, 3, 0.5), 1.5, accuracy: 1e-6)
        XCTAssertEqual(SesTamponu.kubik(5, 7, 9, 11, 0), 7, accuracy: 1e-6)
    }

    /// 44,1 kHz PC: çıkış 48 kHz'e çevrilir, kesinti olmaz.
    func testHizCevirme() {
        let t = SesTamponu(cikisHizi: 48000, mod: .dengeli)
        var sira: UInt32 = 0, konum: UInt32 = 0
        func paket() -> [UInt8] {
            var b = [UInt8]()
            Baslik(tur: .ses, oturum: 1, sira: sira, konum: konum, kare: 160, kanal: 2, hiz: 44100).yaz(&b)
            b += [UInt8](repeating: 0x10, count: 640)
            sira += 1; konum += 160
            return b
        }
        var simdi = 0.0
        var uret = 0.0, oku = 0.0
        for _ in 0..<2000 {
            if uret <= oku + 0.1 { ver(t, paket(), simdi); uret += 160 / 44100.0; simdi = uret }
            if oku < uret - 0.03 { _ = cek(t, 240); oku += 240 / 48000.0 }
        }
        XCTAssertEqual(t.ist.bosalma, 0, "\(t.ist)")
        XCTAssertEqual(t.ist.girisHizi, 44100)
    }
}

final class OdakTestleri: XCTestCase {
    func testGecis() {
        let o = OdakMotoru()
        o.donusGecikmesi = 0.5
        XCTAssertNil(o.guncelle(digerSesCaliyor: false, simdi: 0))
        XCTAssertEqual(o.guncelle(digerSesCaliyor: true, simdi: 1), .telefonaGecti)
        XCTAssertEqual(o.pcKazanci, 0)
        XCTAssertNil(o.guncelle(digerSesCaliyor: false, simdi: 2))      // susma başladı
        XCTAssertNil(o.guncelle(digerSesCaliyor: true, simdi: 2.2))     // reels arası boşluk: geri dönmedi
        XCTAssertNil(o.guncelle(digerSesCaliyor: false, simdi: 3))
        XCTAssertEqual(o.guncelle(digerSesCaliyor: false, simdi: 3.6), .pcyeDondu)
        XCTAssertEqual(o.pcKazanci, 1)
    }

    func testKisVeKapali() {
        let o = OdakMotoru()
        o.mod = .kis
        _ = o.guncelle(digerSesCaliyor: true, simdi: 0)
        XCTAssertEqual(o.pcKazanci, 0.25)
        o.otomatik = false
        XCTAssertEqual(o.guncelle(digerSesCaliyor: true, simdi: 1), .pcyeDondu)
        XCTAssertEqual(o.pcKazanci, 1)
    }
}

final class KaristiriciTestleri: XCTestCase {
    func testOdakRampasi() {
        let k = Karistirici()
        k.ses = 1
        var l = [Float](repeating: 1, count: 4800), r = l
        // önce kazanç yumuşatması otursun
        for _ in 0..<20 {
            l = [Float](repeating: 1, count: 4800); r = l
            l.withUnsafeMutableBufferPointer { a in r.withUnsafeMutableBufferPointer { b in k.isle(sol: a.baseAddress!, sag: b.baseAddress!, n: 4800, hiz: 48000) } }
        }
        XCTAssertEqual(l.last!, 1, accuracy: 0.01)
        k.odakHedef = 0
        k.gecisSuresi = 0.05
        l = [Float](repeating: 1, count: 4800); r = l
        l.withUnsafeMutableBufferPointer { a in r.withUnsafeMutableBufferPointer { b in k.isle(sol: a.baseAddress!, sag: b.baseAddress!, n: 4800, hiz: 48000) } }
        XCTAssertGreaterThan(l[100], 0.5)  // ani kesilmez
        XCTAssertEqual(l.last!, 0, accuracy: 0.001)
    }

    func testBirlestir() {
        var a = Ayarlar()
        a.ses = 0.3
        let b = a.birlestir(Data("{\"ses\":0.9,\"eqAcik\":true,\"gecikme\":\"kararli\",\"bilinmeyen\":5}".utf8))!
        XCTAssertEqual(b.ses, 0.9, accuracy: 0.0001)
        XCTAssertTrue(b.eqAcik)
        XCTAssertEqual(b.gecikme, .kararli)
        XCTAssertEqual(b.gecisModu, a.gecisModu)
        XCTAssertEqual(Mesaj.coz(Data("{\"t\":\"watch\",\"on\":true}".utf8)), .watch(true))
        if case let .set(d)? = Mesaj.coz(Data("{\"t\":\"set\",\"settings\":{\"mono\":true}}".utf8)) {
            XCTAssertTrue(a.birlestir(d)!.mono)
        } else { XCTFail("set çözülemedi") }
    }

    func testAyarlarGeriyeUyumlu() throws {
        let eski = Data("{\"ses\":0.5,\"gecisModu\":\"kis\"}".utf8)
        let a = try JSONDecoder().decode(Ayarlar.self, from: eski)
        XCTAssertEqual(a.ses, 0.5)
        XCTAssertEqual(a.gecisModu, .kis)
        XCTAssertEqual(a.gecikme, .enDusuk, "eski kayıt düşük gecikmeye taşınır")
        XCTAssertTrue(a.pcSesiniKapat)
        XCTAssertEqual(a.eqKazanclari.count, 10)
    }
}
