// PC sesini çalan ve (açıksa) AirPods mikrofonunu dinleyen ses motoru.
//
// Zincir: kaynak (tampon + karıştırıcı) → ekolayzer → ses yükseltici → ana karıştırıcı → AirPods
//
// ⚠️ Ses oturumu "mixWithOthers": başka uygulamalar çalarken bizi KESMEZ; onların çaldığını
//    secondaryAudioShouldBeSilencedHint ile anlayıp PC sesini kendimiz kısarız (bkz. Cekirdek/Odak.swift).
// ⚠️ Motor bağlıyken hiç durmaz (PC sessizken sessizlik çalar): uygulama arka planda canlı kalır.

import AVFoundation
import AudioToolbox
import Cekirdek
import os

/// Ses iş parçacığında kullanılabilecek kadar hafif kilit.
final class Kilit: @unchecked Sendable {
    private let k: UnsafeMutablePointer<os_unfair_lock_s>
    init() {
        k = .allocate(capacity: 1)
        k.initialize(to: os_unfair_lock_s())
    }
    deinit { k.deallocate() }
    @inline(__always) func kilitle() { os_unfair_lock_lock(k) }
    @inline(__always) func ac() { os_unfair_lock_unlock(k) }
}

final class SesMotoru: @unchecked Sendable {
    static let hiz = 48000.0

    let kilit = Kilit()
    let tampon = SesTamponu(cikisHizi: SesMotoru.hiz)
    let karistirici = Karistirici()
    /// Kulaklık yokken (hoparlöre düşünce) PC sesi çıkmasın.
    var kulaklikYok = false

    private let motor = AVAudioEngine()
    private let bicim = AVAudioFormat(standardFormatWithSampleRate: SesMotoru.hiz, channels: 2)!
    private var kaynak: AVAudioSourceNode!
    private let eq = AVAudioUnitEQ(numberOfBands: Ekolayzer.bantlar.count)
    private let yukseltici = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private var mikDugumu: AVAudioSinkNode?
    private(set) var mikAcik = false
    private(set) var calisiyor = false

    /// Mikrofon örnekleri (mono, `hiz` Hz). Ağ kuyruğunda çağrılır.
    var mikrofonCikisi: (([Float], Double) -> Void)?
    private let mikKuyrugu = DispatchQueue(label: "syncyourpods.mik", qos: .userInteractive)

    init() {
        kaynak = AVAudioSourceNode(format: bicim) { [unowned self] _, _, kareSayisi, abl -> OSStatus in
            let liste = UnsafeMutableAudioBufferListPointer(abl)
            guard liste.count >= 2,
                  let sol = liste[0].mData?.assumingMemoryBound(to: Float.self),
                  let sag = liste[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(kareSayisi)
            kilit.kilitle()
            tampon.oku(n, sol: sol, sag: sag)
            if kulaklikYok {
                for i in 0..<n { sol[i] = 0; sag[i] = 0 }
            }
            karistirici.isle(sol: sol, sag: sag, n: n, hiz: SesMotoru.hiz)
            kilit.ac()
            return noErr
        }
        motor.attach(kaynak)
        motor.attach(eq)
        motor.attach(yukseltici)
        for (i, f) in Ekolayzer.bantlar.enumerated() {
            let b = eq.bands[i]
            b.filterType = i == 0 ? .lowShelf : (i == Ekolayzer.bantlar.count - 1 ? .highShelf : .parametric)
            b.frequency = f
            b.bandwidth = 1.0
            b.gain = 0
            b.bypass = false
        }
        eq.bypass = true
        yukseltici.bypass = true
        baglantilariKur()
    }

    private func baglantilariKur() {
        motor.connect(kaynak, to: eq, format: bicim)
        motor.connect(eq, to: yukseltici, format: bicim)
        motor.connect(yukseltici, to: motor.mainMixerNode, format: bicim)
    }

    // MARK: Oturum

    /// Ses oturumunu kurar ve motoru başlatır. Mikrofon durumu değişince yeniden çağrılır.
    /// `gorusme`: mikrofon kapalıyken de AirPods'u görüşme (HFP) yoluna alır — Bluetooth gecikmesi çok düşer,
    /// ses mono ve boğuklaşır. Oyun/video eşzamanlılığı için deneysel seçenek.
    func baslat(mikrofon: Bool, yuksekKalite: Bool, yalitim: Bool, gorusme: Bool = false) throws {
        let oturum = AVAudioSession.sharedInstance()
        if calisiyor { durdur() }
        if mikrofon {
            var secenek: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetooth]
            if #available(iOS 26.0, *), yuksekKalite {
                // AirPods'un yüksek kaliteli kayıt kipi (H2 çipli AirPods + iOS 26): HFP'nin kalite kaybını azaltır.
                secenek.insert(.bluetoothHighQualityRecording)
            }
            try oturum.setCategory(.playAndRecord, mode: yalitim ? .voiceChat : .default, options: secenek)
        } else if gorusme {
            try oturum.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])
        } else {
            try oturum.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? oturum.setPreferredSampleRate(SesMotoru.hiz)
        try? oturum.setPreferredIOBufferDuration(0.005)
        try oturum.setActive(true)

        if mikrofon {
            let giris = motor.inputNode
            try? giris.setVoiceProcessingEnabled(yalitim)
            let girisBicimi = giris.outputFormat(forBus: 0)
            let hiz = girisBicimi.sampleRate
            let dugum = AVAudioSinkNode { [weak self] _, kare, abl -> OSStatus in
                guard let self, let cikis = self.mikrofonCikisi else { return noErr }
                let liste = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: abl))
                guard let p = liste.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                let ornek = Array(UnsafeBufferPointer(start: p, count: Int(kare)))
                self.mikKuyrugu.async { cikis(ornek, hiz) }
                return noErr
            }
            motor.attach(dugum)
            motor.connect(giris, to: dugum, format: girisBicimi)
            mikDugumu = dugum
        }
        mikAcik = mikrofon
        motor.prepare()
        try motor.start()
        calisiyor = true
    }

    func durdur() {
        motor.stop()
        if let d = mikDugumu {
            motor.disconnectNodeInput(d)
            motor.detach(d)
            mikDugumu = nil
            try? motor.inputNode.setVoiceProcessingEnabled(false)
        }
        mikAcik = false
        calisiyor = false
    }

    /// Kesinti (arama, Siri) bitince.
    func surdur() {
        guard !motor.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? motor.start()
        calisiyor = motor.isRunning
    }

    var motorCalisiyor: Bool { motor.isRunning }

    // MARK: Ayarlar

    func uygula(_ a: Ayarlar) {
        kilit.kilitle()
        karistirici.ses = a.ses
        karistirici.denge = a.denge
        karistirici.mono = a.mono
        karistirici.gecisSuresi = a.gecisSuresi
        tampon.mod = a.gecikme
        kilit.ac()

        eq.bypass = !a.eqAcik
        let k = a.eqKazanclari
        for (i, b) in eq.bands.enumerated() where i < k.count {
            b.gain = k[i]
        }
        eq.globalGain = Ekolayzer.onKisma(k)

        let au = yukseltici.audioUnit
        switch a.yukseltici {
        case .kapali:
            yukseltici.bypass = true
        case .hafif:
            yukseltici.bypass = false
            ayarla(au, kDynamicsProcessorParam_Threshold, -20)
            ayarla(au, kDynamicsProcessorParam_HeadRoom, 8)
            ayarla(au, kDynamicsProcessorParam_AttackTime, 0.005)
            ayarla(au, kDynamicsProcessorParam_ReleaseTime, 0.15)
            ayarla(au, kDynamicsProcessorParam_OverallGain, 4)
        case .guclu:
            yukseltici.bypass = false
            ayarla(au, kDynamicsProcessorParam_Threshold, -30)
            ayarla(au, kDynamicsProcessorParam_HeadRoom, 4)
            ayarla(au, kDynamicsProcessorParam_AttackTime, 0.002)
            ayarla(au, kDynamicsProcessorParam_ReleaseTime, 0.1)
            ayarla(au, kDynamicsProcessorParam_OverallGain, 10)
        }
    }

    private func ayarla(_ au: AudioUnit, _ p: AudioUnitParameterID, _ v: Float) {
        AudioUnitSetParameter(au, p, kAudioUnitScope_Global, 0, v, 0)
    }

    func odakKazanci(_ k: Float) {
        kilit.kilitle()
        karistirici.odakHedef = k
        kilit.ac()
    }

    /// Ağdan gelen paket (ağ kuyruğunda).
    func paketAl(_ veri: Data, simdi: Double) {
        kilit.kilitle()
        veri.withUnsafeBytes { tampon.al($0, simdi: simdi) }
        kilit.ac()
    }

    func sifirla() {
        kilit.kilitle()
        tampon.sifirla()
        kilit.ac()
    }

    /// Arayüz için anlık görüntü.
    func olcum() -> (TamponIstatistik, Float) {
        kilit.kilitle()
        defer { kilit.ac() }
        return (tampon.ist, karistirici.seviye)
    }

    /// Bluetooth'un kendi gecikmesi dahil çıkış gecikmesi (ms).
    var cikisGecikmesiMs: Double {
        let o = AVAudioSession.sharedInstance()
        return (o.outputLatency + o.ioBufferDuration) * 1000
    }
}
