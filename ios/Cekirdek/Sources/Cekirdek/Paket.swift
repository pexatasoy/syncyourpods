// Telefonla PC arasındaki dil. Ayrıntı: PLAN.md "Protokol (v1)".
// ⚠️ PC tarafındaki karşılığı pc/src/protokol.rs — ikisi birlikte değişir.
//    Ortak altın örnek: Rust `altin_baslik` ve buradaki `testAltinBaslik` aynı baytları bekler.

import Foundation

public enum Protokol {
    public static let port: UInt16 = 47800
    public static let surum = 1
    public static let servis = "_syncpods._tcp"
    public static let baslik = 24
    public static let kare = 160
    public static let yedekVar: UInt16 = 1
    public static let bicimS16: UInt8 = 1
}

public enum PaketTuru: UInt8 {
    case ses = 1, sessizlik = 2, mikrofon = 3, punch = 4
}

public struct Baslik: Equatable {
    public var tur: PaketTuru
    public var bayrak: UInt16
    public var oturum: UInt32
    public var sira: UInt32
    public var konum: UInt32
    public var kare: UInt16
    public var kanal: UInt8
    public var bicim: UInt8
    public var hiz: UInt32

    public init(tur: PaketTuru, bayrak: UInt16 = 0, oturum: UInt32, sira: UInt32 = 0, konum: UInt32 = 0,
                kare: UInt16 = 0, kanal: UInt8 = 1, bicim: UInt8 = Protokol.bicimS16, hiz: UInt32 = 48000) {
        self.tur = tur; self.bayrak = bayrak; self.oturum = oturum; self.sira = sira; self.konum = konum
        self.kare = kare; self.kanal = kanal; self.bicim = bicim; self.hiz = hiz
    }

    public func yaz(_ b: inout [UInt8]) {
        b.append(0x53)
        b.append(tur.rawValue)
        Self.ekle(&b, bayrak)
        Self.ekle(&b, oturum)
        Self.ekle(&b, sira)
        Self.ekle(&b, konum)
        Self.ekle(&b, kare)
        b.append(kanal)
        b.append(bicim)
        Self.ekle(&b, hiz)
    }

    private static func ekle<T: FixedWidthInteger>(_ b: inout [UInt8], _ v: T) {
        withUnsafeBytes(of: v.littleEndian) { b.append(contentsOf: $0) }
    }

    public static func oku(_ p: UnsafeRawBufferPointer) -> Baslik? {
        guard p.count >= Protokol.baslik, p[0] == 0x53, let tur = PaketTuru(rawValue: p[1]) else { return nil }
        func u16(_ i: Int) -> UInt16 { UInt16(p[i]) | UInt16(p[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 { UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24 }
        return Baslik(tur: tur, bayrak: u16(2), oturum: u32(4), sira: u32(8), konum: u32(12),
                      kare: u16(16), kanal: p[18], bicim: p[19], hiz: u32(20))
    }

    public static func oku(_ d: [UInt8]) -> Baslik? {
        d.withUnsafeBytes { oku($0) }
    }
}

/// Mikrofon paketi: mono s16.
public func mikrofonPaketi(oturum: UInt32, sira: UInt32, konum: UInt32, hiz: UInt32, ornekler: UnsafeBufferPointer<Float>) -> [UInt8] {
    var b = [UInt8]()
    b.reserveCapacity(Protokol.baslik + ornekler.count * 2)
    Baslik(tur: .mikrofon, oturum: oturum, sira: sira, konum: konum, kare: UInt16(ornekler.count), kanal: 1, hiz: hiz).yaz(&b)
    for s in ornekler {
        let v = Int16(max(-1, min(1, s)) * 32767)
        b.append(UInt8(truncatingIfNeeded: v))
        b.append(UInt8(truncatingIfNeeded: v >> 8))
    }
    return b
}

public func punchPaketi(oturum: UInt32) -> [UInt8] {
    var b = [UInt8]()
    Baslik(tur: .punch, oturum: oturum).yaz(&b)
    return b
}

// MARK: - Denetim kanalı (TCP, satır başına bir JSON)

public enum Mesaj: Equatable {
    // telefon → PC
    case hello(id: String, name: String)
    case focus(phone: Bool)
    case settings(pauseMedia: Bool)
    case mic(on: Bool)
    case ping(ts: UInt64)
    case bye
    // PC → telefon
    case welcome(pc: String, id: String, session: UInt32)
    case wait
    case denied
    case status(PCDurumu)
    case micState(String)
    case pong(ts: UInt64)
}

public struct PCDurumu: Equatable, Codable {
    public var playing: Bool
    public var device: String
    public var title: String?
    public var artist: String?
    public var app: String?
    public var pauseMedia: Bool
    public init(playing: Bool = false, device: String = "", title: String? = nil, artist: String? = nil, app: String? = nil, pauseMedia: Bool = true) {
        self.playing = playing; self.device = device; self.title = title; self.artist = artist; self.app = app; self.pauseMedia = pauseMedia
    }
}

extension Mesaj {
    public func satir() -> Data {
        var s: [String: Any] = [:]
        switch self {
        case let .hello(id, name): s = ["t": "hello", "v": Protokol.surum, "id": id, "name": name]
        case let .focus(p): s = ["t": "focus", "phone": p]
        case let .settings(p): s = ["t": "settings", "pauseMedia": p]
        case let .mic(on): s = ["t": "mic", "on": on]
        case let .ping(ts): s = ["t": "ping", "ts": ts]
        case .bye: s = ["t": "bye"]
        case let .welcome(pc, id, session): s = ["t": "welcome", "v": Protokol.surum, "pc": pc, "id": id, "session": session, "udp": Protokol.port]
        case .wait: s = ["t": "wait"]
        case .denied: s = ["t": "denied"]
        case let .status(d): s = ["t": "status", "playing": d.playing, "device": d.device, "pauseMedia": d.pauseMedia]
            if let x = d.title { s["title"] = x }; if let x = d.artist { s["artist"] = x }; if let x = d.app { s["app"] = x }
        case let .micState(x): s = ["t": "micstate", "state": x]
        case let .pong(ts): s = ["t": "pong", "ts": ts]
        }
        var d = (try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys])) ?? Data()
        d.append(0x0A)
        return d
    }

    public static func coz(_ satir: Data) -> Mesaj? {
        guard let j = try? JSONSerialization.jsonObject(with: satir) as? [String: Any], let t = j["t"] as? String else { return nil }
        func sayi(_ k: String) -> UInt64? { (j[k] as? NSNumber)?.uint64Value }
        func mantik(_ k: String) -> Bool? { (j[k] as? NSNumber)?.boolValue }
        func metin(_ k: String) -> String? { j[k] as? String }
        switch t {
        case "hello": return .hello(id: metin("id") ?? "", name: metin("name") ?? "")
        case "focus": return .focus(phone: mantik("phone") ?? false)
        case "settings": return .settings(pauseMedia: mantik("pauseMedia") ?? true)
        case "mic": return .mic(on: mantik("on") ?? false)
        case "ping": return .ping(ts: sayi("ts") ?? 0)
        case "bye": return .bye
        case "welcome": return .welcome(pc: metin("pc") ?? "PC", id: metin("id") ?? "", session: UInt32(truncatingIfNeeded: sayi("session") ?? 0))
        case "wait": return .wait
        case "denied": return .denied
        case "status":
            return .status(PCDurumu(playing: mantik("playing") ?? false, device: metin("device") ?? "",
                                    title: metin("title"), artist: metin("artist"), app: metin("app"),
                                    pauseMedia: mantik("pauseMedia") ?? true))
        case "micstate": return .micState(metin("state") ?? "off")
        case "pong": return .pong(ts: sayi("ts") ?? 0)
        default: return nil
        }
    }
}
