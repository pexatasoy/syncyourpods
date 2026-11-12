// Ana ekranın yapı taşları. Dil: Apple'ın kendi uygulamaları — sistem renkleri, yumuşak köşeler,
// az ama anlamlı hareket.

import SwiftUI
import Cekirdek

enum Renk {
    static let pc = Color(red: 0.04, green: 0.52, blue: 1.0)       // sistem mavisi
    static let telefon = Color(red: 1.0, green: 0.62, blue: 0.04)  // sistem turuncusu
    static let sessiz = Color(.systemGray)

    static func kaynak(_ k: Kaynak) -> Color {
        switch k {
        case .pc: return pc
        case .telefon: return telefon
        case .sessiz, .yok: return sessiz
        }
    }
}

/// Yuvarlak köşeli kart zemini.
struct Kart<Icerik: View>: View {
    var bosluk: CGFloat = 16
    @ViewBuilder var icerik: Icerik
    var body: some View {
        icerik
            .padding(bosluk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Ortadaki kulaklık: çalarken sesle nefes alan halkalar.
struct KulaklikGosterge: View {
    var simge: String
    var renk: Color
    var seviye: Float
    var aktif: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !aktif)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let s = Double(min(1, seviye * 1.6))
            ZStack {
                if aktif {
                    ForEach(0..<3, id: \.self) { i in
                        let faz = (t * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(renk.opacity((1 - faz) * (0.18 + 0.4 * s)), lineWidth: 2)
                            .scaleEffect(1 + faz * (0.35 + 0.45 * s))
                    }
                }
                Circle()
                    .fill(renk.opacity(aktif ? 0.16 : 0.08))
                    .scaleEffect(1 + 0.06 * s)
                Circle()
                    .fill(
                        LinearGradient(colors: [renk.opacity(0.95), renk.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    )
                    .padding(26)
                    .shadow(color: renk.opacity(0.35), radius: 18, y: 8)
                Image(systemName: simge)
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 190, height: 190)
            .animation(.smooth(duration: 0.5), value: renk)
        }
    }
}

/// PC → iPhone → AirPods zinciri; sesin hangi yoldan geldiğini akan noktalarla gösterir.
struct AkisZinciri: View {
    var pcAdi: String
    var kulaklikSimge: String
    var kaynak: Kaynak
    var kulaklik: Bool

    var body: some View {
        HStack(spacing: 0) {
            Dugum(simge: "desktopcomputer", ad: pcAdi, vurgu: kaynak == .pc ? Renk.pc : nil, soluk: kaynak == .yok)
            Hat(akiyor: kaynak == .pc, renk: Renk.pc, acik: kaynak != .yok)
            Dugum(simge: "iphone", ad: "iPhone", vurgu: kaynak == .telefon ? Renk.telefon : nil, soluk: false)
            Hat(akiyor: (kaynak == .pc || kaynak == .telefon) && kulaklik, renk: Renk.kaynak(kaynak), acik: kulaklik)
            Dugum(simge: kulaklikSimge, ad: L("Kulaklık", "AirPods"), vurgu: nil, soluk: !kulaklik)
        }
        .padding(.vertical, 4)
    }

    struct Dugum: View {
        var simge: String
        var ad: String
        var vurgu: Color?
        var soluk: Bool
        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: simge)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(vurgu ?? Color.primary)
                    .frame(width: 52, height: 52)
                    .background((vurgu ?? Color(.tertiarySystemFill)).opacity(vurgu == nil ? 1 : 0.15), in: Circle())
                    .overlay(Circle().strokeBorder(vurgu ?? .clear, lineWidth: 1.5))
                Text(ad)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 84)
            }
            .opacity(soluk ? 0.4 : 1)
            .animation(.smooth, value: vurgu)
        }
    }

    struct Hat: View {
        var akiyor: Bool
        var renk: Color
        var acik: Bool
        var body: some View {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !akiyor)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                GeometryReader { g in
                    let w = g.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(akiyor ? renk.opacity(0.25) : Color(.tertiarySystemFill))
                            .frame(height: 3)
                            .opacity(acik ? 1 : 0.4)
                        if akiyor {
                            ForEach(0..<3, id: \.self) { i in
                                let faz = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                                Circle()
                                    .fill(renk)
                                    .frame(width: 6, height: 6)
                                    .offset(x: faz * (w - 6))
                                    .opacity(sin(faz * .pi))
                            }
                        }
                    }
                    .frame(height: g.size.height)
                }
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 2)
            .offset(y: -11)
        }
    }
}

/// Kontrol Merkezi tarzı kare kutucuk.
struct Kutucuk: View {
    var simge: String
    var baslik: String
    var alt: String
    var acik: Bool
    var renk: Color = Renk.pc

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: simge)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(acik ? .white : .primary)
                .frame(width: 38, height: 38)
                .background(acik ? renk : Color(.tertiarySystemFill), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(baslik).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(alt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.smooth(duration: 0.25), value: acik)
    }
}

/// Ekolayzer eğrisi (önizleme ve düzenleme ekranı ortak).
struct EqEgrisi: View {
    var kazanclar: [Float]
    var renk: Color = Renk.pc

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let n = kazanclar.count
            let noktalar: [CGPoint] = kazanclar.enumerated().map { i, k in
                CGPoint(x: w * CGFloat(i) / CGFloat(max(1, n - 1)),
                        y: h / 2 - CGFloat(k / Ekolayzer.sinir) * (h / 2 - 4))
            }
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2)) }
                    .stroke(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                yumusak(noktalar)
                    .stroke(renk, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                yumusakAlan(noktalar, h: h)
                    .fill(LinearGradient(colors: [renk.opacity(0.25), renk.opacity(0)], startPoint: .top, endPoint: .bottom))
            }
        }
        .animation(.smooth, value: kazanclar)
    }

    private func yumusak(_ p: [CGPoint]) -> Path {
        Path { yol in
            guard let ilk = p.first else { return }
            yol.move(to: ilk)
            for i in 1..<p.count {
                let a = p[i - 1], b = p[i]
                let o = (b.x - a.x) / 2
                yol.addCurve(to: b, control1: CGPoint(x: a.x + o, y: a.y), control2: CGPoint(x: b.x - o, y: b.y))
            }
        }
    }

    private func yumusakAlan(_ p: [CGPoint], h: CGFloat) -> Path {
        var yol = yumusak(p)
        if let son = p.last, let ilk = p.first {
            yol.addLine(to: CGPoint(x: son.x, y: h))
            yol.addLine(to: CGPoint(x: ilk.x, y: h))
            yol.closeSubpath()
        }
        return yol
    }
}
