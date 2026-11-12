// Ana ekran: tek bakışta bağlantı panosu. Ayrıntılar alt menülerde.

import SwiftUI
import Cekirdek

struct AnaEkran: View {
    @Environment(Denetci.self) private var d
    @Environment(\.scenePhase) private var faz
    @State private var yol: [Sayfa] = []

    var body: some View {
        @Bindable var d = d
        NavigationStack(path: $yol) {
            ScrollView {
                VStack(spacing: 22) {
                    ust
                    if d.durum.bagli {
                        bagliIcerik
                    } else {
                        bagliDegilIcerik
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SyncYourPods").font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { AyarlarEkrani() } label: {
                        Image(systemName: "gearshape").font(.body.weight(.medium))
                    }
                    .accessibilityLabel(L("Ayarlar", "Settings"))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Sayfa.self) { $0.gorunum }
        }
        .onAppear {
            #if DEBUG
            if let e = UserDefaults.standard.string(forKey: "ekran"), let s = Sayfa(rawValue: e) { yol = [s] }
            #endif
        }
        .sensoryFeedback(.impact(weight: .light), trigger: d.gecisSayaci) { _, _ in d.ayarlar.titresim }
        .onChange(of: faz, initial: true) { _, yeni in
            if yeni == .active { d.oneGeldi() } else if yeni == .background { d.arkayaGitti() }
        }
    }

    // MARK: Üst: kulaklık + durum

    private var ust: some View {
        let renk = d.rota.kulaklik ? Renk.kaynak(d.kaynak) : Renk.sessiz
        let aktif = d.kaynak == .pc || d.kaynak == .telefon
        return VStack(spacing: 14) {
            KulaklikGosterge(simge: d.rota.simge, renk: renk, seviye: d.kaynak == .pc ? d.seviye : (aktif ? 0.25 : 0), aktif: aktif && d.rota.kulaklik)
                .padding(.top, 8)
            VStack(spacing: 4) {
                Text(d.rota.ad)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(d.durumMetni)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: d.durumMetni)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bağlıyken

    @ViewBuilder private var bagliIcerik: some View {
        @Bindable var d = d
        Kart {
            AkisZinciri(pcAdi: d.pcAdi ?? "PC", kulaklikSimge: d.rota.simge, kaynak: d.kaynak, kulaklik: d.rota.kulaklik)
        }

        if let pc = d.pc, let baslik = pc.title, !baslik.isEmpty {
            Kart {
                HStack(spacing: 14) {
                    Image(systemName: pc.playing ? "waveform" : "pause.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Renk.pc)
                        .symbolEffect(.variableColor.iterative, isActive: pc.playing && !d.telefonda)
                        .frame(width: 44, height: 44)
                        .background(Renk.pc.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(baslik).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text([pc.artist, pc.app].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if d.telefonda && d.ayarlar.medyaDuraklat {
                        Text(L("Duraklatıldı", "Paused")).font(.caption2.weight(.medium)).foregroundStyle(Renk.telefon)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Renk.telefon.opacity(0.12), in: Capsule())
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        Kart {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Bilgisayar sesi", "Computer volume")).font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $d.ayarlar.ses, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            Button {
                d.ayarlar.mikAcik.toggle()
            } label: {
                Kutucuk(simge: d.ayarlar.mikAcik ? "mic.fill" : "mic.slash.fill", baslik: L("Mikrofon", "Microphone"),
                        alt: mikAlt, acik: d.ayarlar.mikAcik, renk: .red)
            }
            Button {
                d.ayarlar.otomatikGecis.toggle()
            } label: {
                Kutucuk(simge: "arrow.left.arrow.right", baslik: L("Otomatik geçiş", "Auto switching"),
                        alt: d.ayarlar.otomatikGecis ? L("Açık", "On") : L("Kapalı", "Off"), acik: d.ayarlar.otomatikGecis, renk: Renk.telefon)
            }
            NavigationLink { EkolayzerEkrani() } label: {
                Kutucuk(simge: "slider.vertical.3", baslik: L("Ekolayzer", "Equalizer"),
                        alt: d.ayarlar.eqAcik ? eqAdi : L("Kapalı", "Off"), acik: d.ayarlar.eqAcik, renk: .indigo)
            }
            NavigationLink { GecikmeEkrani() } label: {
                Kutucuk(simge: "timer", baslik: L("Gecikme", "Latency"),
                        alt: "≈ \(Int(d.toplamGecikmeMs.rounded())) ms", acik: false)
            }
        }
        .buttonStyle(.plain)

        if d.ayarlar.mikAcik {
            Label(L("Mikrofon açıkken AirPods telefon görüşmesi kipine geçer, dinlediğin sesin kalitesi düşer.", "With the mic on, AirPods switch to phone-call mode and what you're listening to sounds worse."), systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .transition(.opacity)
        }
        if d.mikDurumu == "noDevice" {
            NavigationLink { MikrofonEkrani() } label: {
                Label(L("Bilgisayarda sanal mikrofon yok. Kurulum için dokun.", "No virtual microphone on the computer. Tap to set it up."), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }

        NavigationLink { TanilamaEkrani() } label: {
            HStack(spacing: 6) {
                Circle().fill(baglantiRengi).frame(width: 7, height: 7)
                Text(altSatir)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var mikAlt: String {
        guard d.ayarlar.mikAcik else { return L("Kapalı", "Off") }
        switch d.mikDurumu {
        case "on": return L("Açık", "On")
        case "noDevice": return L("Sanal mikrofon yok", "No virtual mic")
        case "error": return L("Hata", "Error")
        default: return L("Açılıyor…", "Starting…")
        }
    }

    private var eqAdi: String {
        d.ayarlar.eqHazir == "ozel" ? L("Özel", "Custom") : (Ekolayzer.hazir(d.ayarlar.eqHazir)?.ad ?? L("Açık", "On"))
    }

    private var kayipYuzde: Double {
        let i = d.ist
        guard i.alinan > 0 else { return 0 }
        return Double(i.kayip) / Double(i.alinan + i.kayip) * 100
    }

    private var baglantiRengi: Color {
        if d.ist.bosalma > 5 || kayipYuzde > 1 { return .orange }
        return .green
    }

    private var altSatir: String {
        var s = "\(d.pcAdi ?? "PC") · \(Int(d.ist.girisHizi / 1000)) kHz"
        if let r = d.rttMs { s += L(" · ağ \(Int(r.rounded())) ms", " · network \(Int(r.rounded())) ms") }
        s += String(format: L(" · kayıp %%%.1f", " · loss %.1f%%"), kayipYuzde)
        return s
    }

    // MARK: Bağlı değilken

    @ViewBuilder private var bagliDegilIcerik: some View {
        switch d.durum {
        case let .izinBekleniyor(ad):
            Kart {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("İzin bekleniyor", "Waiting for permission")).font(.subheadline.weight(.semibold))
                        Text(L("\(ad) ekranında çıkan pencerede “Evet”e bas. Bu yalnızca bir kez sorulur.", "Click “Yes” in the window that pops up on \(ad). You're only asked once."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    ProgressView()
                }
            }
        case let .reddedildi(ad):
            Kart {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("\(ad) bağlantıya izin vermedi.", "\(ad) didn't allow the connection.")).font(.subheadline.weight(.semibold))
                    if let pc = d.bulunanlar.first(where: { $0.ad == ad }) {
                        Button(L("Yeniden dene", "Try again")) { d.baglan(pc) }.buttonStyle(.borderedProminent)
                    }
                }
            }
        case .baglaniyor:
            Kart {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L("Bağlanıyor…", "Connecting…")).font(.subheadline)
                }
            }
        default:
            EmptyView()
        }

        if !d.bulunanlar.isEmpty && !isBaglaniyor {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("AĞDAKİ BİLGİSAYARLAR", "COMPUTERS ON YOUR NETWORK")).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(d.bulunanlar) { pc in
                        Button { d.baglan(pc) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer").foregroundStyle(Renk.pc).frame(width: 28)
                                Text(pc.ad).foregroundStyle(.primary)
                                Spacer()
                                Text(L("Bağlan", "Connect")).font(.subheadline.weight(.medium)).foregroundStyle(Renk.pc)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if pc.id != d.bulunanlar.last?.id { Divider().padding(.leading, 56) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }

        if d.bulunanlar.isEmpty {
            Kart(bosluk: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Başlarken", "Getting started")).font(.headline)
                    Adim(no: 1, metin: L("Bilgisayarına SyncYourPods’u kur ve aç. Saatin yanında simgesi görünür.", "Install and open SyncYourPods on your computer. Its icon shows up next to the clock."))
                    Adim(no: 2, metin: L("iPhone ile bilgisayar aynı ağda olsun (bilgisayar kabloyla da bağlı olabilir).", "Put your iPhone and the computer on the same network (the computer can be on a cable)."))
                    Adim(no: 3, metin: L("Bilgisayarda çıkan izin penceresine “Evet” de. Gerisi kendiliğinden.", "Click “Yes” in the permission window on the computer. The rest happens by itself."))
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("Ağda bilgisayar aranıyor…", "Looking for computers on the network…")).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }

        if let h = d.sonHata, !d.durum.bagli {
            Text(h).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var isBaglaniyor: Bool {
        if case .baglaniyor = d.durum { return true }
        if case .izinBekleniyor = d.durum { return true }
        return false
    }

    struct Adim: View {
        var no: Int
        var metin: String
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Text("\(no)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Renk.pc, in: Circle())
                Text(metin).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Doğrudan açılabilen sayfalar (ekran görüntüsü ve ileride derin bağlantı için).
enum Sayfa: String, Hashable {
    case ayarlar, ses, ekolayzer, gecis, gecikme, mikrofon, tanilama, gurultu, bilgisayar

    @ViewBuilder var gorunum: some View {
        switch self {
        case .ayarlar: AyarlarEkrani()
        case .ses: SesEkrani()
        case .ekolayzer: EkolayzerEkrani()
        case .gecis: GecisEkrani()
        case .gecikme: GecikmeEkrani()
        case .mikrofon: MikrofonEkrani()
        case .tanilama: TanilamaEkrani()
        case .gurultu: GurultuEkrani()
        case .bilgisayar: BilgisayarlarEkrani()
        }
    }
}
