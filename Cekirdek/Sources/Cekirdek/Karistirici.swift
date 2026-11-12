// Tampondan çıkan PC sesine ses seviyesi, denge, mono ve geçiş (odak) kazancını uygular.
// Ekolayzer ve ses yükseltici iOS'ta AVAudioUnit olarak ayrıca zincirde.
// ⚠️ Ses iş parçacığında çalışır: bellek ayırma yok.

import Foundation

public final class Karistirici {
    /// 0…1 kaydırıcı değeri; kulağa doğrusal gelsin diye karesi alınır.
    public var ses: Float = 0.8
    /// -1 tam sol … +1 tam sağ
    public var denge: Float = 0
    public var mono = false
    /// Geçiş kuralının istediği PC kazancı (1 = tam, 0 = sessiz).
    public var odakHedef: Float = 1
    /// Odak değişiminde yumuşak geçiş süresi (sn).
    public var gecisSuresi: Double = 0.25

    public private(set) var odakSimdi: Float = 1
    private var kazancSimdi: Float = 0.64
    /// Arayüzdeki ses dalgası için yumuşatılmış tepe seviyesi (0…1).
    public private(set) var seviye: Float = 0

    public init() {}

    public func isle(sol: UnsafeMutablePointer<Float>, sag: UnsafeMutablePointer<Float>, n: Int, hiz: Double) {
        let hedefKazanc = ses * ses
        let odakAdim = Float(1 / max(0.001, gecisSuresi * hiz))
        let solK: Float = denge > 0 ? 1 - denge : 1
        let sagK: Float = denge < 0 ? 1 + denge : 1
        var tepe: Float = 0
        for i in 0..<n {
            // Ses kaydırıcısı: tek kutuplu yumuşatma (cızırtı olmasın).
            kazancSimdi += (hedefKazanc - kazancSimdi) * 0.002
            if odakSimdi < odakHedef { odakSimdi = min(odakHedef, odakSimdi + odakAdim) }
            else if odakSimdi > odakHedef { odakSimdi = max(odakHedef, odakSimdi - odakAdim) }
            // Kulağa doğal gelsin: odak kazancı da karesel.
            let g = kazancSimdi * odakSimdi * odakSimdi
            var l = sol[i], r = sag[i]
            if mono { let m = (l + r) * 0.5; l = m; r = m }
            l *= g * solK
            r *= g * sagK
            sol[i] = l; sag[i] = r
            tepe = max(tepe, abs(l), abs(r))
        }
        seviye = max(tepe, seviye * 0.92)
    }
}
