// Ayarlar: Apple Ayarlar uygulamasının dili — gruplu liste, renkli küçük simgeler, açıklayıcı alt notlar.

import SwiftUI
import Cekirdek

struct AyarSimgesi: View {
    var ad: String
    var renk: Color
    var body: some View {
        Image(systemName: ad)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(renk, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct AyarSatiri: View {
    var simge: String
    var renk: Color
    var baslik: String
    var deger: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            AyarSimgesi(ad: simge, renk: renk)
            Text(baslik)
            Spacer()
            if let deger { Text(deger).foregroundStyle(.secondary) }
        }
    }
}

struct AyarlarEkrani: View {
    @Environment(Denetci.self) private var d

    var body: some View {
        @Bindable var d = d
        List {
            Section {
                NavigationLink { BilgisayarlarEkrani() } label: {
                    AyarSatiri(simge: "desktopcomputer", renk: Renk.pc, baslik: "Bilgisayar",
                               deger: d.durum.bagli ? (d.pcAdi ?? "Bağlı") : "Bağlı değil")
                }
            }

            Section("Ses") {
                NavigationLink { SesEkrani() } label: {
                    AyarSatiri(simge: "speaker.wave.2.fill", renk: .pink, baslik: "Ses", deger: "%\(Int(d.ayarlar.ses * 100))")
                }
                NavigationLink { EkolayzerEkrani() } label: {
                    AyarSatiri(simge: "slider.vertical.3", renk: .indigo, baslik: "Ekolayzer",
                               deger: d.ayarlar.eqAcik ? (d.ayarlar.eqHazir == "ozel" ? "Özel" : (Ekolayzer.hazir(d.ayarlar.eqHazir)?.ad ?? "Açık")) : "Kapalı")
                }
                NavigationLink { GecikmeEkrani() } label: {
                    AyarSatiri(simge: "timer", renk: .teal, baslik: "Gecikme", deger: GecikmeEkrani.ad(d.ayarlar.gecikme))
                }
            }

            Section("AirPods") {
                NavigationLink { GecisEkrani() } label: {
                    AyarSatiri(simge: "arrow.left.arrow.right", renk: Renk.telefon, baslik: "Otomatik Geçiş",
                               deger: d.ayarlar.otomatikGecis ? "Açık" : "Kapalı")
                }
                NavigationLink { MikrofonEkrani() } label: {
                    AyarSatiri(simge: "mic.fill", renk: .red, baslik: "Mikrofon", deger: d.ayarlar.mikAcik ? "Açık" : "Kapalı")
                }
                NavigationLink { GurultuEkrani() } label: {
                    AyarSatiri(simge: "ear.fill", renk: .gray, baslik: "Gürültü Engelleme")
                }
            }

            Section {
                Toggle(isOn: $d.ayarlar.titresim) {
                    AyarSatiri(simge: "iphone.radiowaves.left.and.right", renk: .purple, baslik: "Geçişte titreşim")
                }
            }

            Section {
                NavigationLink { TanilamaEkrani() } label: {
                    AyarSatiri(simge: "waveform.path.ecg", renk: .green, baslik: "Tanılama")
                }
                NavigationLink { HakkindaEkrani() } label: {
                    AyarSatiri(simge: "info", renk: .gray, baslik: "Hakkında")
                }
            }
        }
        .navigationTitle("Ayarlar")
    }
}

// MARK: - Ses

struct SesEkrani: View {
    @Environment(Denetci.self) private var d

    var body: some View {
        @Bindable var d = d
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bilgisayar sesi")
                        Spacer()
                        Text("%\(Int(d.ayarlar.ses * 100))").foregroundStyle(.secondary).monospacedDigit()
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $d.ayarlar.ses, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Yalnız bilgisayardan gelen sesi etkiler. Genel ses düzeyi iPhone’un ses tuşlarıyla.")
            }

            Section {
                VStack(spacing: 8) {
                    HStack {
                        Text("Denge")
                        Spacer()
                        Text(dengeMetni).foregroundStyle(.secondary).monospacedDigit()
                    }
                    HStack(spacing: 12) {
                        Text("Sol").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { d.ayarlar.denge }, set: { y in
                            // Ortaya yakınsa ortaya otur.
                            d.ayarlar.denge = abs(y) < 0.06 ? 0 : y
                        }), in: -1...1)
                        Text("Sağ").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Toggle("Mono ses", isOn: $d.ayarlar.mono)
            } footer: {
                Text("Mono, iki kulağa aynı sesi verir: tek AirPods taktığında hiçbir şey kaçmaz.")
            }

            Section {
                Toggle("Bilgisayarın kendi sesi kapalı", isOn: $d.ayarlar.pcSesiniKapat)
            } footer: {
                Text("Bağlıyken bilgisayarın hoparlörü ya da kulaklığı susar, ses yalnız AirPods’ta olur. Bağlantı bitince eski hâline döner.")
            }

            Section {
                Picker("Ses yükseltici", selection: $d.ayarlar.yukseltici) {
                    Text("Kapalı").tag(Yukseltici.kapali)
                    Text("Hafif").tag(Yukseltici.hafif)
                    Text("Güçlü").tag(Yukseltici.guclu)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Ses yükseltici")
            } footer: {
                Text("Kısık konuşmaları yükseltir, ani patlamaları bastırır. Sessiz videolar ve gece dinlemesi için.")
            }
        }
        .navigationTitle("Ses")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dengeMetni: String {
        let v = d.ayarlar.denge
        if v == 0 { return "Orta" }
        return v < 0 ? "Sol %\(Int(-v * 100))" : "Sağ %\(Int(v * 100))"
    }
}

// MARK: - Ekolayzer

struct EkolayzerEkrani: View {
    @Environment(Denetci.self) private var d

    var body: some View {
        @Bindable var d = d
        List {
            Section {
                Toggle("Ekolayzer", isOn: $d.ayarlar.eqAcik.animation())
            }

            Section {
                EqEgrisi(kazanclar: d.ayarlar.eqKazanclari, renk: d.ayarlar.eqAcik ? .indigo : Color(.systemGray3))
                    .frame(height: 120)
                    .padding(.vertical, 8)
                HStack {
                    ForEach(Ekolayzer.etiketler, id: \.self) { e in
                        Text(e).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
            }

            // Özel seçiliyse kaydırıcılar eğrinin hemen altında: kaydırmadan görülsün.
            if d.ayarlar.eqHazir == "ozel" {
                Section {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<Ekolayzer.bantlar.count, id: \.self) { i in
                            DikeyKaydirici(deger: Binding(get: { d.ayarlar.eqOzel[i] }, set: { d.ayarlar.eqOzel[i] = $0 }),
                                           etiket: Ekolayzer.etiketler[i])
                        }
                    }
                    .frame(height: 210)
                    .padding(.vertical, 6)
                    Button("Sıfırla", role: .destructive) {
                        d.ayarlar.eqOzel = Array(repeating: 0, count: Ekolayzer.bantlar.count)
                    }
                } header: {
                    Text("Özel ayar")
                } footer: {
                    Text("±12 dB. Kırpılmayı önlemek için yükselttiğin kadar genel ses kendiliğinden biraz kısılır.")
                }
            }

            Section("Hazır ayarlar") {
                ForEach(Ekolayzer.hazirlar) { h in
                    secenek(h.ad, secili: d.ayarlar.eqHazir == h.id) {
                        d.ayarlar.eqHazir = h.id
                        d.ayarlar.eqAcik = true
                    }
                }
                secenek("Özel", secili: d.ayarlar.eqHazir == "ozel") {
                    if d.ayarlar.eqHazir != "ozel" { d.ayarlar.eqOzel = d.ayarlar.eqKazanclari }
                    d.ayarlar.eqHazir = "ozel"
                    d.ayarlar.eqAcik = true
                }
            }
        }
        .navigationTitle("Ekolayzer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func secenek(_ ad: String, secili: Bool, sec: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.smooth) { sec() } }) {
            HStack {
                Text(ad).foregroundStyle(.primary)
                Spacer()
                if secili { Image(systemName: "checkmark").foregroundStyle(.indigo).fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Ekolayzer için dikey kaydırıcı.
struct DikeyKaydirici: View {
    @Binding var deger: Float
    var etiket: String

    var body: some View {
        VStack(spacing: 6) {
            Text(deger == 0 ? "0" : String(format: "%+.0f", deger))
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(deger == 0 ? Color.secondary : Color.indigo)
            GeometryReader { g in
                let h = g.size.height
                let y = h / 2 - CGFloat(deger / Ekolayzer.sinir) * (h / 2)
                ZStack(alignment: .top) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(width: 4)
                        .frame(maxWidth: .infinity)
                    Capsule().fill(Color.indigo)
                        .frame(width: 4, height: abs(y - h / 2))
                        .offset(y: min(y, h / 2))
                        .frame(maxWidth: .infinity)
                    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .frame(width: 20, height: 20)
                        .offset(y: y - 10)
                        .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let v = Float((h / 2 - g.location.y) / (h / 2)) * Ekolayzer.sinir
                    let yuvarla = (max(-Ekolayzer.sinir, min(Ekolayzer.sinir, v)) * 2).rounded() / 2
                    if yuvarla != deger { deger = yuvarla }
                })
            }
            Text(etiket).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: deger)
    }
}

// MARK: - Otomatik geçiş

struct GecisEkrani: View {
    @Environment(Denetci.self) private var d

    var body: some View {
        @Bindable var d = d
        List {
            Section {
                Toggle("Otomatik geçiş", isOn: $d.ayarlar.otomatikGecis.animation())
            } footer: {
                Text("iPhone’da bir video ya da müzik başlayınca AirPods ona geçer; bitince bilgisayarın sesi geri gelir.")
            }

            if d.ayarlar.otomatikGecis {
                Section("iPhone sesi gelince bilgisayar") {
                    SecimSatiri(baslik: "Susar", aciklama: "Yalnız iPhone duyulur.", secili: d.ayarlar.gecisModu == .sustur) { d.ayarlar.gecisModu = .sustur }
                    SecimSatiri(baslik: "Kısılır", aciklama: "Bilgisayar arka planda alçak sesle devam eder.", secili: d.ayarlar.gecisModu == .kis) { d.ayarlar.gecisModu = .kis }
                    SecimSatiri(baslik: "Karışır", aciklama: "İkisi birlikte duyulur, geçiş yapılmaz.", secili: d.ayarlar.gecisModu == .karistir) { d.ayarlar.gecisModu = .karistir }
                    if d.ayarlar.gecisModu == .kis {
                        HStack {
                            Text("Arka plan sesi")
                            Slider(value: $d.ayarlar.kisSeviyesi, in: 0.05...0.6)
                        }
                    }
                }

                Section {
                    Toggle("Bilgisayardaki medyayı duraklat", isOn: $d.ayarlar.medyaDuraklat)
                } footer: {
                    Text("YouTube, Spotify ya da film iPhone sesi çalarken duraklar, iPhone sesi bitince kaldığı yerden sürer. Yalnız SyncYourPods’un duraklattığı şey sürdürülür.")
                }

                Section {
                    Picker("Geri dönüş", selection: $d.ayarlar.donusGecikmesi) {
                        Text("Hemen").tag(0.3)
                        Text("Kısa").tag(0.6)
                        Text("Uzun").tag(1.5)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Geçiş yumuşaklığı")
                            Spacer()
                            Text("\(Int(d.ayarlar.gecisSuresi * 1000)) ms").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $d.ayarlar.gecisSuresi, in: 0.05...1.0)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Geri dönüş, iPhone sesi sustuktan sonra beklenen süre: Reels gibi art arda videolarda gidip gelmeyi önler.")
                }
            }

            Section {
                Label {
                    Text("iPhone’da müzik çalarken bilgisayara dönmek için AirPods’a bir kez bas: iPhone’daki müzik durur, bilgisayarın sesi hemen gelir.")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "hand.tap.fill").foregroundStyle(Renk.telefon)
                }
            } footer: {
                Text("iOS, başka bir uygulamanın sesini arka plandan durdurmamıza izin vermiyor; bu yön senin dokunuşunla olur.")
            }
        }
        .navigationTitle("Otomatik Geçiş")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SecimSatiri: View {
    var baslik: String
    var aciklama: String
    var secili: Bool
    var sec: () -> Void
    var body: some View {
        Button(action: sec) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(baslik).foregroundStyle(.primary)
                    Text(aciklama).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if secili { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gecikme

struct GecikmeEkrani: View {
    @Environment(Denetci.self) private var d

    static func ad(_ m: GecikmeModu) -> String {
        switch m {
        case .enDusuk: return "En düşük"
        case .dengeli: return "Dengeli"
        case .kararli: return "Kararlı"
        }
    }

    var body: some View {
        @Bindable var d = d
        List {
            Section {
                VStack(spacing: 6) {
                    Text("\(Int(d.toplamGecikmeMs.rounded())) ms")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.smooth, value: Int(d.toplamGecikmeMs / 5))
                    Text("bilgisayardan kulağa toplam gecikme")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Parca(ad: "Ağ", ms: (d.rttMs ?? 0) / 2, renk: .teal)
                        Parca(ad: "Tampon", ms: d.ist.tamponMs, renk: Renk.pc)
                        Parca(ad: "Bluetooth", ms: d.cikisGecikmesiMs, renk: .indigo)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section {
                SecimSatiri(baslik: "En düşük", aciklama: "Oyun ve video için. Ağ zayıfsa ara ara cızırtı olabilir.", secili: d.ayarlar.gecikme == .enDusuk) { d.ayarlar.gecikme = .enDusuk }
                SecimSatiri(baslik: "Dengeli", aciklama: "Çoğu ev ağı için en iyisi.", secili: d.ayarlar.gecikme == .dengeli) { d.ayarlar.gecikme = .dengeli }
                SecimSatiri(baslik: "Kararlı", aciklama: "Müzik ve podcast için. Kalabalık ağda bile kesilmez.", secili: d.ayarlar.gecikme == .kararli) { d.ayarlar.gecikme = .kararli }
            } footer: {
                Text("Tampon, ağın o anki durumuna göre kendini ayarlar.")
            }

            Section {
                Toggle("Görüşme kipi", isOn: $d.ayarlar.gorusmeKipi)
            } header: {
                Text("Deneysel")
            } footer: {
                Text("En büyük pay Bluetooth’un. Görüşme kipinde AirPods telefon görüşmesindeki gibi bağlanır: gecikme belirgin düşer ama ses mono ve daha boğuk olur. Oyun ve dudak senkronu için dene, müzik için kapalı tut.")
            }
        }
        .navigationTitle("Gecikme")
        .navigationBarTitleDisplayMode(.inline)
    }

    struct Parca: View {
        var ad: String
        var ms: Double
        var renk: Color
        var body: some View {
            VStack(spacing: 2) {
                Text("\(Int(ms.rounded()))").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(renk)
                Text(ad).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Mikrofon

struct MikrofonEkrani: View {
    @Environment(Denetci.self) private var d

    var body: some View {
        @Bindable var d = d
        List {
            Section {
                Toggle("AirPods mikrofonu", isOn: $d.ayarlar.mikAcik.animation())
            } footer: {
                Text("Açıkken AirPods telefon görüşmesi kipine geçer: konuşabilirsin ama dinlediğin sesin kalitesi düşer. İşin bitince kapat.")
            }

            if d.mikIzniReddedildi {
                Section {
                    Label("Mikrofon izni kapalı. Ayarlar → SyncYourPods → Mikrofon.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Ayarları aç") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                }
            }

            Section {
                Toggle("Yüksek kalite", isOn: $d.ayarlar.mikYuksekKalite)
                Toggle("Ses yalıtımı", isOn: $d.ayarlar.mikSesYalitimi)
            } footer: {
                Text("Yüksek kalite, iOS 26 ve H2 çipli AirPods’ta (AirPods Pro 2, AirPods 4) kalite kaybını azaltır. Ses yalıtımı arka plandaki gürültüyü ve yankıyı bastırır.")
            }

            Section {
                HStack {
                    Text("Bilgisayar")
                    Spacer()
                    Text(pcDurumu).foregroundStyle(d.mikDurumu == "noDevice" || d.mikDurumu == "error" ? .orange : .secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    AnaEkran.Adim(no: 1, metin: "Bilgisayara ücretsiz VB-CABLE’ı kur (vb-audio.com/Cable) ve bilgisayarı yeniden başlat.")
                    AnaEkran.Adim(no: 2, metin: "Discord, Zoom ya da Teams’te mikrofon olarak “CABLE Output”u seç.")
                    AnaEkran.Adim(no: 3, metin: "Buradan mikrofonu aç. SyncYourPods sesi kendisi oraya verir.")
                }
                .padding(.vertical, 6)
                Link(destination: URL(string: "https://vb-audio.com/Cable/")!) {
                    Label("VB-CABLE indirme sayfası", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Bilgisayarda bir kez")
            }
        }
        .navigationTitle("Mikrofon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pcDurumu: String {
        guard d.durum.bagli else { return "Bağlı değil" }
        switch d.mikDurumu {
        case "on": return "Mikrofon alınıyor"
        case "noDevice": return "VB-CABLE bulunamadı"
        case "error": return "Hata"
        default: return d.ayarlar.mikAcik ? "Açılıyor…" : "Kapalı"
        }
    }
}

// MARK: - Bilgisayarlar

struct BilgisayarlarEkrani: View {
    @Environment(Denetci.self) private var d

    var body: some View {
        @Bindable var d = d
        List {
            Section {
                if d.bulunanlar.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Aranıyor…").foregroundStyle(.secondary)
                    }
                }
                ForEach(d.bulunanlar) { pc in
                    Button { d.baglan(pc) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer").foregroundStyle(Renk.pc).frame(width: 28)
                            Text(pc.ad).foregroundStyle(.primary)
                            Spacer()
                            if d.pcAdi == pc.ad && d.durum.bagli {
                                Image(systemName: "checkmark").foregroundStyle(Renk.pc).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } header: {
                Text("Ağdaki bilgisayarlar")
            } footer: {
                Text("Bilgisayarda SyncYourPods açık olmalı ve iPhone ile aynı ağda olmalı. Windows ilk açılışta güvenlik duvarı izni sorarsa “Özel ağlar”a izin ver.")
            }

            Section {
                Toggle("Otomatik bağlan", isOn: $d.ayarlar.otomatikBaglan)
            } footer: {
                Text("Uygulama açılınca son bilgisayara kendiliğinden bağlanır.")
            }

            if d.durum.bagli {
                Section {
                    Button("Bağlantıyı kes", role: .destructive) { d.kes() }
                }
            }
        }
        .navigationTitle("Bilgisayar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Gürültü engelleme

struct GurultuEkrani: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    HStack(spacing: 22) {
                        mod("person.wave.2.fill", "Gürültü\nEngelleme")
                        mod("ear.fill", "Uyarlanabilir")
                        mod("person.2.wave.2.fill", "Ortam\nSesi")
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            } footer: {
                Text("Dinleme kipi AirPods’un kendi ayarıdır. Apple bu ayarın başka uygulamalarca değiştirilmesine izin vermiyor; SyncYourPods sesini hangi kipte olursan ol aynen taşır.")
            }

            Section("Kipi değiştirmek için") {
                Label("AirPods’un sapını basılı tut.", systemImage: "hand.point.up.left.fill")
                Label("Kontrol Merkezi’nde ses kaydırıcısını basılı tut.", systemImage: "switch.2")
                Label("Ayarlar → AirPods’un adı.", systemImage: "gearshape.fill")
            }
        }
        .navigationTitle("Gürültü Engelleme")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func mod(_ simge: String, _ ad: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: simge)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 54, height: 54)
                .background(Color(.tertiarySystemFill), in: Circle())
            Text(ad).font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tanılama

struct TanilamaEkrani: View {
    @Environment(Denetci.self) private var d

    var body: some View {
        @Bindable var d = d
        let i = d.ist
        List {
            Section("Geçiş") {
                Satir("Öncelikli ses ipucu", d.ipucu ? "Var" : "Yok", vurgu: d.ipucu)
                Satir("Başka ses çalıyor", d.digerSes ? "Evet" : "Hayır", vurgu: d.digerSes)
                Satir("Ses nerede", d.telefonda ? "iPhone" : "Bilgisayar")
                Toggle("Geniş algılama", isOn: $d.ayarlar.genisAlgilama)
            }
            Section("Tampon") {
                Satir("Durum", i.durum == .caliyor ? "Çalıyor" : (i.durum == .doluyor ? "Doluyor" : "Boş"))
                Satir("Doluluk / hedef", String(format: "%.0f / %.0f ms", i.tamponMs, i.hedefMs))
                Satir("Ağ titreşimi", String(format: "%.1f ms", i.titremeMs))
                Satir("Saat kayması", String(format: "%+.0f ppm", i.kaymaPpm))
                Satir("Giriş hızı", "\(Int(i.girisHizi)) Hz")
            }
            Section("Paketler") {
                Satir("Alınan", "\(i.alinan)")
                Satir("Yedekten kurtarılan", "\(i.kurtarilan)")
                Satir("Kayıp (örtülen)", "\(i.kayip)", vurgu: i.kayip > 0)
                Satir("Geç gelen", "\(i.gec)")
                Satir("Boşalma", "\(i.bosalma)", vurgu: i.bosalma > 0)
                Satir("Atlama", "\(i.atlama)")
            }
            Section("Çıkış") {
                Satir("Rota", d.rota.ad)
                Satir("Bluetooth + iOS", String(format: "%.0f ms", d.cikisGecikmesiMs))
                if let r = d.rttMs { Satir("Ağ gidiş-dönüş", String(format: "%.0f ms", r)) }
                Satir("Mikrofon (PC)", d.mikDurumu)
            }
        }
        .navigationTitle("Tanılama")
        .navigationBarTitleDisplayMode(.inline)
        .monospacedDigit()
    }

    struct Satir: View {
        var a: String, b: String, vurgu: Bool
        init(_ a: String, _ b: String, vurgu: Bool = false) { self.a = a; self.b = b; self.vurgu = vurgu }
        var body: some View {
            HStack {
                Text(a)
                Spacer()
                Text(b).foregroundStyle(vurgu ? Color.orange : Color.secondary)
            }
        }
    }
}

// MARK: - Hakkında

struct HakkindaEkrani: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(LinearGradient(colors: [Renk.pc, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text("SyncYourPods").font(.title3.weight(.semibold))
                    Text("Sürüm \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                Text("Bluetooth’u olmayan bilgisayarın sesini, aynı ağdaki iPhone üzerinden AirPods’a taşır. Ses yalnız evinin ağında dolaşır; hiçbir sunucuya gitmez.")
            }
        }
        .navigationTitle("Hakkında")
        .navigationBarTitleDisplayMode(.inline)
    }
}
