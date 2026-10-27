# SyncYourPods

Bluetooth'u olmayan Windows PC'nin sesini, aynı ağdaki iPhone üzerinden AirPods'a taşır.
Kulaklık hep telefona bağlı kalır; değişen yalnız telefonun hangi sesi çaldığı → geçiş anlık.

Fikir ve kararlar: Efe, 2026-10-27.

## Kilitli kararlar
- **Deneme değil ürün.** Apple dilinde, çok sade ana ekran (bağlantı panosu), her şey alt menülerde.
- **Windows tarafı Rust** (`pc/`): tepside durur, kaynak harcamaz. Telefon bağlı değilken ses YAKALAMAZ.
- **iPhone tarafı SwiftUI** (`ios/`), iOS 18+, iOS 26 özellikleri `#available` ile.
- **Kurulum Ad Hoc** (doğrudan link): App Store / TestFlight YOK → Apple incelemesi yok, 4.3 riskine girmez.
  Efe'nin iPhone 16'sı geliştirici hesabında kayıtlı. Yeni cihaz = profile ekle + yeniden derle.
- PC'de ses çıkışı VAR (Efe: monitör/hoparlör görünüyor) → sürücüsüz WASAPI loopback.
- Mikrofon: aç/kapa ayarı, "kalite düşer" notu. iOS 26'da `bluetoothHighQualityRecording` ile kayıp azaltılır.
  PC'de sanal mikrofon için VB-CABLE (ücretsiz) gerekir — program yoksa kurulum adımını gösterir.
- **Gürültü engelleme uygulamadan değiştirilemez** (Apple'ın açık API'si yok). Efe'ye söylendi.

## Geçiş kuralı (ürünün kalbi)
iPhone uygulaması "karışabilir" (mixWithOthers) ses oturumuyla PC sesini sürekli çalar.
`secondaryAudioShouldBeSilencedHint` başka bir uygulamanın ses çalmaya başladığını söyler:
- Telefonda başka ses başladı → PC sesi yumuşakça kısılır, PC'deki medya (isteğe bağlı) DURAKLATILIR.
- O ses bitti → kısa bekleme (titreşimi önler) → PC sesi geri gelir, duraklattığımız medya devam eder.
- Telefonda müzik çalarken PC'ye dönmek: AirPods'a bir kez bas → telefon müziği durur → PC anında gelir.
  (iOS başka uygulamanın sesini arka plandan kesmemize izin vermiyor; bu yüzden bu yön kullanıcının dokunuşuyla.)

⚠️ Belirsiz: hint arka planda sorgulanınca güvenilir mi? Tanılama ekranı canlı gösterir; gerçek cihazda doğrulanacak.

## Protokol (v1)
- **Keşif:** PC Bonjour ile `_syncpods._tcp` yayınlar (port 47800). TXT: `v=1`, `id`, `name`.
- **Denetim:** TCP 47800, satır başına bir JSON. Telefon `hello` → PC (yeni cihazsa onay penceresi) → `welcome`.
- **Ses:** UDP 47800. Telefon aynı porta 1 sn'de bir `punch` atar; PC sesi o adrese yollar.
  Ham PCM s16le, paket başına 160 kare (48 kHz'de 3,3 ms), bir önceki parça yedek olarak pakette → kayıp telafisi.
  Sıkıştırma YOK: kodlama gecikmesi sıfır, PC'de CPU harcamaz (~3 Mbit/s, yerel ağda önemsiz).
- **Paket başlığı (20 bayt, little endian):**
  `0 u8 'S'` · `1 u8 tür (1 ses, 2 sessizlik, 3 mikrofon, 4 punch)` · `2 u16 bayrak (bit0 yedek var)` ·
  `4 u32 oturum` · `8 u32 sıra` · `12 u32 örnek konumu` · `16 u16 kare sayısı` · `18 u8 kanal` · `19 u8 biçim (1=s16le)`
- Sessizlikte PC ses göndermez, 100 ms'de bir `sessizlik` paketi atar.
- Saat kayması: telefon tampon doluluğuna göre çok küçük oranlı yeniden örnekleme yapar (Cekirdek/Tampon).

## Klasörler
- `pc/` — Rust, `x86_64-pc-windows-gnu` sunucuda çapraz derlenir: `cd pc && cargo build --release --target x86_64-pc-windows-gnu`
- `ios/Cekirdek` — saf Swift (paket, tampon, geçiş kuralı); Linux'ta `swift test`
- `ios/SyncYourPods` — SwiftUI uygulaması; derleme GitHub macOS koşucusunda (Medowl hattının kopyası, Ad Hoc dışa aktarma)
- `site/` — indirme sayfası (iPhone kurulum linki + Windows programı)

## Adresler / komutlar
- İndirme sayfası: https://chainmedia.co/fotoyol/<site/.site-dizini>/ (`site/yayinla.sh`) — iPhone itms-services + Windows exe
- iOS kaynak zip'i: `ios/yayinla-ios.sh` → `ios/ci/kos.sh tetikle|bekle|hata|indir` (depo pexatasoy/fotoaktar-masaustu, akış `syncyourpods.yml`)
- Ad Hoc profil: `ios/ci/adhoc_kur.py kur|yenile` → /root/.asc/syncyourpods-adhoc.mobileprovision → `ci/kos.sh sir` (gizli SYNC_PROFIL)
  ⚠️ `sir` (GitHub gizli değişkeni yazma) otomatik kipte engellendi → Efe onayı/elle.
- Uçtan uca deneme (Linux): `cd pc && cargo run &` sonra `python3 araclar/sahte_telefon.py` ya da `cd ios/Cekirdek && swift run uctanuca`
- PC günlüğü: %APPDATA%\SyncYourPods\gunluk.txt (tepsi → Günlüğü aç)

## ▶ KALDIĞIMIZ YER
- 2026-10-27: Windows programı + çekirdek + iPhone uygulaması + indirme sayfası yazıldı. Rust testleri, Swift çekirdek
  testleri (12) ve Rust↔Swift uçtan uca deneme geçti. SYNC_PROFIL Efe onayıyla yazıldı (2026-10-27); iPhone derleme 2
  (Ad Hoc, iPhone 16, profil 2027-09-04'e kadar) indirme sayfasında. Kurulum bildirimi manifest.xml (Caddy .plist'e tür vermiyor).
- Gerçek cihazda doğrulanacak: (1) hint arka planda geliyor mu (Tanılama ekranı), (2) gecikme/kesinti, (3) WASAPI loopback
  gerçek PC'de, (4) VB-CABLE mikrofonu, (5) medya duraklat/sürdür (Chrome/Spotify).
- 2026-10-27 akşam: Opera/Defender exe'yi "virüs" diye engelledi. CI'da Defender güncel tanımlarla 3 sürüm de TEMİZ →
  bulut ML (imzasız yeni dosya) kaynaklı. Windows artık MSVC ile GitHub Windows koşucusunda derleniyor (`pc/ci-windows.yml`,
  akış `syncyourpods-windows.yml`, Defender taraması dahil). Kalıcı çözüm kod imzalama sertifikası (ücretli) — Efe'ye soruldu.
- Efe isteği: bağlıyken PC'nin kendi sesi gelmesin → endpoint SetMute (loopback susturulmuş aygıtı da yakalıyor) + oturum
  ölçeriyle denetim (yakalama kesilirse vazgeçer) + çökme izi `susturulan-aygit.txt`. Gecikme: IAudioClient3 en kısa motor
  periyodu, varsayılan En düşük, deneysel "Görüşme kipi" (HFP). iPhone derleme 3.

