// PC'yi bulma (Bonjour) ve PC'yle konuşma (TCP denetim + UDP ses).
// Protokol: PLAN.md "Protokol (v1)", Cekirdek/Paket.swift.

import Foundation
import Network
import Cekirdek

struct BulunanPC: Identifiable, Equatable {
    let id: String
    let ad: String
    let uc: NWEndpoint
}

/// Ağdaki SyncYourPods PC'lerini listeler.
final class Kesif {
    private var tarayici: NWBrowser?
    var degisti: (([BulunanPC]) -> Void)?

    func baslat() {
        guard tarayici == nil else { return }
        let t = NWBrowser(for: .bonjourWithTXTRecord(type: Protokol.servis, domain: nil), using: .tcp)
        t.browseResultsChangedHandler = { [weak self] sonuclar, _ in
            var liste: [BulunanPC] = []
            for s in sonuclar {
                guard case let .service(ad, _, _, _) = s.endpoint else { continue }
                var id = ad, gorunen = ad
                if case let .bonjour(txt) = s.metadata {
                    if let x = txt["id"] { id = x }
                    if let x = txt["name"] { gorunen = x }
                }
                liste.append(BulunanPC(id: id, ad: gorunen, uc: s.endpoint))
            }
            liste.sort { $0.ad < $1.ad }
            DispatchQueue.main.async { self?.degisti?(liste) }
        }
        t.stateUpdateHandler = { [weak self] durum in
            if case .failed = durum {
                self?.tarayici?.cancel()
                self?.tarayici = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.baslat() }
            }
        }
        t.start(queue: .main)
        tarayici = t
    }

    func durdur() {
        tarayici?.cancel()
        tarayici = nil
    }
}

enum BaglantiOlayi {
    case hazir
    case mesaj(Mesaj)
    case koptu(String)
}

/// Tek bir PC ile oturum. Kopunca yeniden kurulmaz: üst katman yenisini açar.
final class Baglanti {
    let pc: BulunanPC
    private let kuyruk = DispatchQueue(label: "syncyourpods.ag", qos: .userInteractive)
    private var tcp: NWConnection
    private var udp: NWConnection?
    private var gelen = Data()
    private var oturum: UInt32 = 0
    private var zamanlayici: DispatchSourceTimer?
    private var uyandirici: DispatchSourceTimer?
    private var sonPong = Date()
    private var bitti = false

    var olay: ((BaglantiOlayi) -> Void)?
    /// Ses paketi geldi (ağ kuyruğunda; doğrudan ses motoruna).
    var sesPaketi: ((Data) -> Void)?
    private(set) var rttMs: Double?

    init(pc: BulunanPC) {
        self.pc = pc
        let tcpAyar = NWProtocolTCP.Options()
        tcpAyar.noDelay = true
        tcpAyar.enableKeepalive = true
        tcpAyar.keepaliveIdle = 2
        let p = NWParameters(tls: nil, tcp: tcpAyar)
        p.serviceClass = .interactiveVoice
        tcp = NWConnection(to: pc.uc, using: p)
    }

    func baslat(telefonId: String, telefonAdi: String) {
        tcp.stateUpdateHandler = { [weak self] d in
            guard let self else { return }
            switch d {
            case .ready:
                self.gonder(.hello(id: telefonId, name: telefonAdi))
                self.oku()
                self.bildir(.hazir)
            case let .failed(e):
                self.bitir("Bağlantı koptu (\(e.localizedDescription))")
            case let .waiting(e):
                self.bitir("PC'ye ulaşılamıyor (\(e.localizedDescription))")
            case .cancelled:
                self.bitir("Bağlantı kapandı")
            default:
                break
            }
        }
        tcp.start(queue: kuyruk)
    }

    func gonder(_ m: Mesaj) {
        tcp.send(content: m.satir(), completion: .contentProcessed { _ in })
    }

    func kapat() {
        kuyruk.async {
            guard !self.bitti else { return }
            self.gonder(.bye)
            self.kuyruk.asyncAfter(deadline: .now() + 0.15) { self.bitir("Bağlantı kesildi") }
        }
    }

    private func bildir(_ o: BaglantiOlayi) {
        DispatchQueue.main.async { self.olay?(o) }
    }

    private func bitir(_ neden: String) {
        guard !bitti else { return }
        bitti = true
        zamanlayici?.cancel()
        uyandirici?.cancel()
        udp?.cancel()
        tcp.cancel()
        bildir(.koptu(neden))
    }

    private func oku() {
        tcp.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] veri, _, tamam, hata in
            guard let self, !self.bitti else { return }
            if let veri { self.gelen.append(veri) }
            while let i = self.gelen.firstIndex(of: 0x0A) {
                let satir = self.gelen.subdata(in: self.gelen.startIndex..<i)
                self.gelen.removeSubrange(self.gelen.startIndex...i)
                if let m = Mesaj.coz(satir) { self.isle(m) }
            }
            if tamam || hata != nil {
                self.bitir("PC bağlantıyı kapattı")
            } else {
                self.oku()
            }
        }
    }

    private func isle(_ m: Mesaj) {
        switch m {
        case let .welcome(_, _, s):
            oturum = s
            udpKur()
        case let .pong(ts):
            sonPong = Date()
            rttMs = Double(Self.ms() &- ts)
        default:
            break
        }
        bildir(.mesaj(m))
    }

    /// TCP hangi adrese bağlandıysa UDP de oraya: Bonjour adı yeniden çözülmesin.
    private func udpKur() {
        var hedef: NWEndpoint = pc.uc
        if let uzak = tcp.currentPath?.remoteEndpoint, case let .hostPort(host, _) = uzak {
            hedef = .hostPort(host: host, port: NWEndpoint.Port(rawValue: Protokol.port)!)
        }
        let p = NWParameters.udp
        p.serviceClass = .interactiveVoice
        let u = NWConnection(to: hedef, using: p)
        u.stateUpdateHandler = { [weak self] d in
            guard let self else { return }
            if case .ready = d { self.punch() }
        }
        u.start(queue: kuyruk)
        udp = u
        udpOku()
        sonPong = Date()
        let z = DispatchSource.makeTimerSource(queue: kuyruk)
        var adim = 0
        z.schedule(deadline: .now() + 0.5, repeating: 1.0)
        z.setEventHandler { [weak self] in
            guard let self, !self.bitti else { return }
            adim += 1
            self.punch()
            if adim % 2 == 0 { self.gonder(.ping(ts: Self.ms())) }
            if Date().timeIntervalSince(self.sonPong) > 6 {
                self.bitir("PC yanıt vermiyor")
            }
        }
        z.resume()
        zamanlayici = z

        // Wi-Fi'ı uyanık tut: ekran kapalıyken iPhone'un Wi-Fi'ı güç tasarrufuna geçer ve gelen paketleri
        // ~100 ms'lik yığınlar hâlinde alır (sesin takılması). Görüntülü arama uygulamaları gibi 20 ms'de bir
        // minik paket (24 bayt) yollamak, erişim noktasının bekleyen paketleri hemen teslim etmesini sağlar.
        let u2 = DispatchSource.makeTimerSource(queue: kuyruk)
        u2.schedule(deadline: .now() + 0.02, repeating: 0.02, leeway: .milliseconds(2))
        u2.setEventHandler { [weak self] in self?.punch() }
        u2.resume()
        uyandirici = u2
    }

    private func punch() {
        guard let u = udp, oturum != 0 else { return }
        u.send(content: Data(punchPaketi(oturum: oturum)), completion: .idempotent)
    }

    private func udpOku() {
        udp?.receiveMessage { [weak self] veri, _, _, hata in
            guard let self, !self.bitti else { return }
            if let veri { self.sesPaketi?(veri) }
            if hata == nil { self.udpOku() }
        }
    }

    /// Mikrofon paketi (mono s16).
    private var mikSira: UInt32 = 0
    private var mikKonum: UInt32 = 0
    func mikrofonGonder(_ ornek: [Float], hiz: Double) {
        kuyruk.async { [weak self] in
            guard let self, let u = self.udp, self.oturum != 0 else { return }
            // MTU'ya sığsın: en fazla 600 örneklik parçalar.
            var i = 0
            while i < ornek.count {
                let n = min(600, ornek.count - i)
                let p = ornek[i..<(i + n)].withUnsafeBufferPointer {
                    mikrofonPaketi(oturum: self.oturum, sira: self.mikSira, konum: self.mikKonum, hiz: UInt32(hiz), ornekler: $0)
                }
                u.send(content: Data(p), completion: .idempotent)
                self.mikSira &+= 1
                self.mikKonum &+= UInt32(n)
                i += n
            }
        }
    }

    static func ms() -> UInt64 {
        UInt64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}
