// Linux'ta uçtan uca deneme: Rust PC programına (deneme sinyaliyle) gerçek soketlerle bağlanır,
// paketleri SesTamponu'na verir, 48 kHz hızında okur. Boşalma/kayıp olmamalı.
//   (cd pc && cargo run) &   →   swift run uctanuca
#if canImport(Glibc)
import Glibc
import Foundation
import Cekirdek

func saat() -> Double { var t = timespec(); clock_gettime(CLOCK_MONOTONIC, &t); return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9 }

var adres = sockaddr_in()
adres.sin_family = sa_family_t(AF_INET)
adres.sin_port = Protokol.port.bigEndian
adres.sin_addr.s_addr = inet_addr("127.0.0.1")
let tcp = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
let ok = withUnsafePointer(to: &adres) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(tcp, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
guard ok == 0 else { print("PC programına bağlanılamadı"); exit(1) }
func yolla(_ m: Mesaj) { let d = m.satir(); _ = d.withUnsafeBytes { send(tcp, $0.baseAddress, d.count, 0) } }
var gelen = Data()
func satirOku() -> Mesaj? {
    var b = [UInt8](repeating: 0, count: 4096)
    while true {
        if let i = gelen.firstIndex(of: 0x0A) { let s = gelen[..<i]; gelen.removeSubrange(...i); return Mesaj.coz(Data(s)) }
        let n = recv(tcp, &b, b.count, 0); if n <= 0 { return nil }
        gelen.append(contentsOf: b[0..<n])
    }
}
yolla(.hello(id: "swift-deneme", name: "Swift Deneme"))
var oturum: UInt32 = 0
while let m = satirOku() { if case let .welcome(_, _, s) = m { oturum = s; break } }
print("oturum:", String(oturum, radix: 16))

let udp = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
var zt = timeval(tv_sec: 0, tv_usec: 1000)
setsockopt(udp, SOL_SOCKET, SO_RCVTIMEO, &zt, socklen_t(MemoryLayout<timeval>.size))
func punch() { let p = punchPaketi(oturum: oturum); _ = p.withUnsafeBytes { b in withUnsafePointer(to: &adres) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(udp, b.baseAddress, p.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } } }
punch()

let t = SesTamponu(cikisHizi: 48000, mod: .enDusuk)
var l = [Float](repeating: 0, count: 240), r = l
var tampon = [UInt8](repeating: 0, count: 2048)
let bas = saat(); var okunan = 0; var sonPunch = bas; var sesli = 0; var enBuyuk: Float = 0
while saat() - bas < 6 {
    let n = recv(udp, &tampon, tampon.count, 0)
    if n > 0 { tampon.withUnsafeBytes { t.al(UnsafeRawBufferPointer(rebasing: $0[0..<n]), simdi: saat()) } }
    // 48 kHz hızında 240'lık bloklar (iOS'un ses iş parçacığı gibi)
    while Double(okunan) < (saat() - bas) * 48000 {
        l.withUnsafeMutableBufferPointer { a in r.withUnsafeMutableBufferPointer { b in t.oku(240, sol: a.baseAddress!, sag: b.baseAddress!) } }
        okunan += 240
        let tepe = l.map(abs).max() ?? 0
        if tepe > 0.01 { sesli += 240 }; enBuyuk = max(enBuyuk, tepe)
    }
    if saat() - sonPunch > 1 { punch(); sonPunch = saat() }
}
yolla(.bye)
let i = t.ist
print(String(format: "alınan %d · kurtarılan %d · kayıp %d · geç %d · boşalma %d · atlama %d", i.alinan, i.kurtarilan, i.kayip, i.gec, i.bosalma, i.atlama))
print(String(format: "tampon %.1f ms · hedef %.1f ms · titreşim %.1f ms · kayma %.0f ppm · sesli %.2f sn · tepe %.2f", i.tamponMs, i.hedefMs, i.titremeMs, i.kaymaPpm, Double(sesli) / 48000, enBuyuk))
// Deneme sinyali 2 sn çalar 1 sn susar: 6 sn'de ≈4 sn ses.
let gecti = i.bosalma <= 1 && i.kayip == 0 && sesli > 48000 * 3 && abs(enBuyuk - 0.3) < 0.02
print(gecti ? "✓ Rust ↔ Swift uçtan uca geçti" : "✗ BAŞARISIZ")
exit(gecti ? 0 : 1)
#else
print("yalnız Linux")
#endif
