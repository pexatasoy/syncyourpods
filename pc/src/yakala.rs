//! PC sesini yakalayıp telefona yollar.
//! Windows: varsayılan çıkış aygıtından WASAPI loopback (sürücü gerekmez).
//! Telefon bağlı değilken aygıt hiç açılmaz → boşta CPU harcamaz.

use crate::gunluk;
use crate::ortak::Ortak;
use crate::paket::Paketleyici;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};

pub fn calistir(o: Arc<Ortak>) {
    loop {
        if !o.aktif.load(Ordering::SeqCst) {
            std::thread::sleep(Duration::from_millis(100));
            continue;
        }
        #[cfg(windows)]
        let sonuc = unsafe { win::yakala(&o) };
        #[cfg(not(windows))]
        let sonuc = deneme_sinyali(&o);
        if let Err(e) = sonuc {
            gunluk!("yakalama hatası: {}", e);
            std::thread::sleep(Duration::from_secs(1));
        }
        if o.durum.lock().unwrap().caliyor {
            o.durum.lock().unwrap().caliyor = false;
            o.durum_gonder();
        }
    }
}

/// "Çalıyor" bilgisi değiştiyse telefona bildir (en fazla 4 kez/sn bakılır).
fn caliyor_bildir(o: &Ortak, p: &Paketleyici, son_bakis: &mut Instant) {
    if son_bakis.elapsed() < Duration::from_millis(250) {
        return;
    }
    *son_bakis = Instant::now();
    let c = p.caliyor();
    let degisti = {
        let mut d = o.durum.lock().unwrap();
        let x = d.caliyor != c;
        d.caliyor = c;
        x
    };
    if degisti {
        o.durum_gonder();
    }
}

/// Linux'ta uçtan uca deneme: 440 Hz, 2 sn çal / 1 sn sus.
#[cfg(not(windows))]
fn deneme_sinyali(o: &Arc<Ortak>) -> Result<(), String> {
    use crate::protokol::KARE;
    let hiz = 48000u32;
    let mut p = Paketleyici::yeni(hiz);
    o.durum.lock().unwrap().cihaz = "Deneme sinyali".into();
    let bas = Instant::now();
    let mut uretilen: u64 = 0;
    let mut son = Instant::now();
    while o.aktif.load(Ordering::SeqCst) {
        let hedef = (bas.elapsed().as_secs_f64() * hiz as f64) as u64;
        let mut ornek = Vec::new();
        while uretilen + (KARE as u64) <= hedef {
            for i in 0..KARE as u64 {
                let n = uretilen + i;
                let sn = n as f64 / hiz as f64;
                let v = if (sn as u64) % 3 == 2 { 0.0 } else { (sn * 440.0 * std::f64::consts::TAU).sin() * 0.3 };
                let s = (v * 32767.0) as i16;
                ornek.push(s);
                ornek.push(s);
            }
            uretilen += KARE as u64;
        }
        let oturum = o.oturum.load(Ordering::SeqCst);
        p.ekle(&ornek, oturum, &mut |b| o.ses_gonder(b));
        caliyor_bildir(o, &p, &mut son);
        std::thread::sleep(Duration::from_millis(3));
    }
    Ok(())
}

#[cfg(windows)]
pub mod win {
    use super::*;
    use crate::paket::stereoya;
    use windows::Win32::Devices::FunctionDiscovery::PKEY_Device_FriendlyName;
    use windows::Win32::Foundation::WAIT_TIMEOUT;
    use windows::Win32::Media::Audio::Endpoints::{IAudioEndpointVolume, IAudioMeterInformation};
    use windows::Win32::Media::Audio::*;
    use windows::Win32::Media::KernelStreaming::WAVE_FORMAT_EXTENSIBLE;
    use windows::Win32::Media::Multimedia::{KSDATAFORMAT_SUBTYPE_IEEE_FLOAT, WAVE_FORMAT_IEEE_FLOAT};
    use windows::Win32::System::Com::*;
    use windows::Win32::System::Threading::*;
    use windows::core::Interface;

    pub struct Bicim {
        pub hiz: u32,
        pub kanal: usize,
        pub bit: u16,
        pub float: bool,
    }

    pub unsafe fn bicim_oku(p: *const WAVEFORMATEX) -> Bicim {
        unsafe {
            let w = &*p;
            let mut float = w.wFormatTag as u32 == WAVE_FORMAT_IEEE_FLOAT;
            if w.wFormatTag as u32 == WAVE_FORMAT_EXTENSIBLE {
                let x = &*(p as *const WAVEFORMATEXTENSIBLE);
                let alt = std::ptr::addr_of!(x.SubFormat).read_unaligned();
                float = alt == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
            }
            Bicim { hiz: w.nSamplesPerSec, kanal: w.nChannels as usize, bit: w.wBitsPerSample, float }
        }
    }

    pub unsafe fn aygit_adi(c: &IMMDevice) -> String {
        unsafe {
            c.OpenPropertyStore(STGM_READ)
                .and_then(|s| s.GetValue(&PKEY_Device_FriendlyName))
                .map(|v| v.to_string())
                .unwrap_or_else(|_| crate::dil::t("Ses aygıtı", "Audio device").into())
        }
    }

    unsafe fn aygit_kimligi(c: &IMMDevice) -> String {
        unsafe {
            match c.GetId() {
                Ok(p) => {
                    let s = p.to_string().unwrap_or_default();
                    CoTaskMemFree(Some(p.0 as *const _));
                    s
                }
                Err(_) => String::new(),
            }
        }
    }

    pub unsafe fn yakala(o: &Arc<Ortak>) -> windows::core::Result<()> {
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            let numara: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
            let aygit = numara.GetDefaultAudioEndpoint(eRender, eConsole)?;
            let kimlik = aygit_kimligi(&aygit);
            let ad = aygit_adi(&aygit);
            o.durum.lock().unwrap().cihaz = ad.clone();
            o.durum_gonder();

            // Bağlıyken PC'nin kendi çıkışı (hoparlör/kulaklık) susar; ses yalnız AirPods'ta.
            let mut sus = Susturucu::yeni(&aygit, &kimlik);
            sus.denetle(o.ayarlar.lock().unwrap().pc_sesini_kapat, true);
            let istemci: IAudioClient = aygit.Activate(CLSCTX_ALL, None)?;
            let bicim_p = istemci.GetMixFormat()?;
            let b = bicim_oku(bicim_p);
            gunluk!("yakalama: {} — {} Hz, {} kanal, {} bit{}", ad, b.hiz, b.kanal, b.bit, if b.float { " float" } else { "" });
            // Düşük gecikme: aynı aygıtta en kısa periyotlu sessiz bir akış açılırsa Windows ses motoru o periyotta
            // döner, loopback paketleri 10 ms yerine ~3 ms'de bir gelir. Olmazsa (başka uygulama kilitlemişse) önemsiz.
            let _hizlandirici = dusuk_gecikme(&aygit, bicim_p);
            istemci.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK, 200_000, 0, bicim_p, None)?;
            let olay = CreateEventW(None, false, false, None)?;
            istemci.SetEventHandle(olay)?;
            let yakalayici: IAudioCaptureClient = istemci.GetService()?;
            istemci.Start()?;

            let mut p = Paketleyici::yeni(b.hiz);
            let mut f32_ara: Vec<f32> = Vec::new();
            let mut stereo: Vec<i16> = Vec::new();
            let mut son_bakis = Instant::now();
            let mut son_aygit_bakisi = Instant::now();
            let sonuc = (|| -> windows::core::Result<()> {
                while o.aktif.load(Ordering::SeqCst) {
                    if son_aygit_bakisi.elapsed() > Duration::from_secs(1) {
                        son_aygit_bakisi = Instant::now();
                        let istek = o.ayarlar.lock().unwrap().pc_sesini_kapat && o.kulaklik.load(Ordering::SeqCst);
                        sus.denetle(istek, p.caliyor());
                        // Kullanıcı varsayılan çıkışı değiştirdiyse yeniden başla.
                        if let Ok(a) = numara.GetDefaultAudioEndpoint(eRender, eConsole) {
                            if aygit_kimligi(&a) != kimlik {
                                gunluk!("varsayılan çıkış değişti");
                                return Ok(());
                            }
                        }
                    }
                    let oturum = o.oturum.load(Ordering::SeqCst);
                    // Windows sessizlikte loopback olayı üretmez. Bazı sürücüler olayı hiç üretmeyebilir:
                    // zaman aşımında da tampona bakılır, gerçekten boşsa sessizlik sayılır.
                    let zaman_asimi = WaitForSingleObject(olay, 20) == WAIT_TIMEOUT;
                    let mut okunan = 0usize;
                    loop {
                        let n = yakalayici.GetNextPacketSize()?;
                        if n == 0 {
                            break;
                        }
                        let mut veri: *mut u8 = std::ptr::null_mut();
                        let mut kare = 0u32;
                        let mut bayrak = 0u32;
                        yakalayici.GetBuffer(&mut veri, &mut kare, &mut bayrak, None, None)?;
                        let toplam = kare as usize * b.kanal;
                        f32_ara.clear();
                        if bayrak & (AUDCLNT_BUFFERFLAGS_SILENT.0 as u32) != 0 || veri.is_null() {
                            f32_ara.resize(toplam, 0.0);
                        } else if b.float && b.bit == 32 {
                            f32_ara.extend_from_slice(std::slice::from_raw_parts(veri as *const f32, toplam));
                        } else if b.bit == 16 {
                            f32_ara.extend(std::slice::from_raw_parts(veri as *const i16, toplam).iter().map(|s| *s as f32 / 32768.0));
                        } else if b.bit == 32 {
                            f32_ara.extend(std::slice::from_raw_parts(veri as *const i32, toplam).iter().map(|s| *s as f32 / 2147483648.0));
                        } else {
                            f32_ara.resize(toplam, 0.0);
                        }
                        yakalayici.ReleaseBuffer(kare)?;
                        stereo.clear();
                        stereoya(&f32_ara, b.kanal, &mut stereo);
                        p.ekle(&stereo, oturum, &mut |x| o.ses_gonder(x));
                        okunan += kare as usize;
                    }
                    if zaman_asimi && okunan == 0 {
                        p.bos(oturum, &mut |x| o.ses_gonder(x));
                    }
                    caliyor_bildir(o, &p, &mut son_bakis);
                }
                Ok(())
            })();
            let _ = istemci.Stop();
            CoTaskMemFree(Some(bicim_p as *const _));
            sus.birak();
            if let Some(h) = &_hizlandirici {
                let _ = h.Stop();
            }
            sonuc
        }
    }

    /// Bağlıyken çıkış aygıtını susturur, giderken eski hâline getirir.
    /// - Loopback susturulmuş aygıtta da sesi yakalar (GStreamer wasapi2 gözlemi); yine de her saniye denetlenir:
    ///   uygulamalar ses çalıyor ama yakalanan ses yoksa bu aygıtta susturma yakalamayı da kesiyor demektir →
    ///   susturma geri alınır ve bu aygıt için bir daha denenmez.
    /// - Kullanıcı PC'nin ses tuşlarına basarsa Windows susturmayı kaldırır → yeniden susturulur.
    /// - Program çökerse PC sessiz kalmasın: diskte iz bırakılır, açılışta `kurtar` geri alır.
    pub struct Susturucu {
        hacim: Option<IAudioEndpointVolume>,
        oturumlar: Option<IAudioSessionManager2>,
        kimlik: String,
        biz_kistik: bool,
        sessiz_ama_calan: u32,
        desteklenmiyor: bool,
    }

    fn iz_yolu() -> std::path::PathBuf {
        crate::ayarlar::klasor().join("susturulan-aygit.txt")
    }

    impl Susturucu {
        pub unsafe fn yeni(aygit: &IMMDevice, kimlik: &str) -> Susturucu {
            unsafe {
                Susturucu {
                    hacim: aygit.Activate(CLSCTX_ALL, None).ok(),
                    oturumlar: aygit.Activate(CLSCTX_ALL, None).ok(),
                    kimlik: kimlik.to_string(),
                    biz_kistik: false,
                    sessiz_ama_calan: 0,
                    desteklenmiyor: DESTEKLENMEYEN.lock().unwrap().contains(&kimlik.to_string()),
                }
            }
        }

        /// Uygulamaların çaldığı en yüksek seviye (aygıt susturmasından ÖNCE ölçülür).
        unsafe fn oturum_tepesi(&self) -> f32 {
            unsafe {
                let Some(m) = &self.oturumlar else { return 0.0 };
                let Ok(liste) = m.GetSessionEnumerator() else { return 0.0 };
                let mut tepe = 0.0f32;
                for i in 0..liste.GetCount().unwrap_or(0) {
                    if let Ok(o) = liste.GetSession(i) {
                        if let Ok(olcer) = o.cast::<IAudioMeterInformation>() {
                            tepe = tepe.max(olcer.GetPeakValue().unwrap_or(0.0));
                        }
                    }
                }
                tepe
            }
        }

        pub unsafe fn denetle(&mut self, istek: bool, yakalanan_caliyor: bool) {
            unsafe {
                let Some(h) = self.hacim.clone() else { return };
                if !istek || self.desteklenmiyor {
                    self.birak();
                    return;
                }
                let susuk = h.GetMute().map(|m| m.as_bool()).unwrap_or(false);
                if !susuk {
                    if h.SetMute(true, std::ptr::null()).is_ok() {
                        if !self.biz_kistik {
                            gunluk!("PC çıkışı susturuldu");
                            let _ = std::fs::write(iz_yolu(), &self.kimlik);
                        }
                        self.biz_kistik = true;
                    }
                    return;
                }
                if !self.biz_kistik {
                    return; // kullanıcı zaten susturmuştu; dokunma
                }
                // Denetim: uygulamalar belirgin ses çalıyor ama yakalanan sessizse 3 sn sonra vazgeç.
                if !yakalanan_caliyor && self.oturum_tepesi() > 0.02 {
                    self.sessiz_ama_calan += 1;
                    if self.sessiz_ama_calan >= 3 {
                        gunluk!("bu aygıtta susturma yakalamayı da kesiyor → susturma kapatıldı");
                        DESTEKLENMEYEN.lock().unwrap().push(self.kimlik.clone());
                        self.desteklenmiyor = true;
                        self.birak();
                    }
                } else {
                    self.sessiz_ama_calan = 0;
                }
            }
        }

        pub unsafe fn birak(&mut self) {
            unsafe {
                if self.biz_kistik {
                    if let Some(h) = &self.hacim {
                        let _ = h.SetMute(false, std::ptr::null());
                    }
                    self.biz_kistik = false;
                    let _ = std::fs::remove_file(iz_yolu());
                    gunluk!("PC çıkışı eski hâline döndü");
                }
            }
        }
    }

    static DESTEKLENMEYEN: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());

    /// Açılışta: önceki oturum çökmüş ve aygıtı susturulmuş bıraktıysa geri aç.
    pub fn kurtar() {
        let Ok(kimlik) = std::fs::read_to_string(iz_yolu()) else { return };
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            if let Ok(n) = CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL) {
                let k: Vec<u16> = kimlik.trim().encode_utf16().chain(std::iter::once(0)).collect();
                if let Ok(a) = n.GetDevice(windows::core::PCWSTR(k.as_ptr())) {
                    if let Ok(h) = a.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None) {
                        let _ = h.SetMute(false, std::ptr::null());
                        gunluk!("önceki oturumdan kalan susturma geri alındı");
                    }
                }
            }
        }
        let _ = std::fs::remove_file(iz_yolu());
    }

    /// Ses motorunu en kısa periyoda çeker (IAudioClient3). Dönen akış yakalama boyunca açık tutulur.
    unsafe fn dusuk_gecikme(aygit: &IMMDevice, bicim: *const WAVEFORMATEX) -> Option<IAudioClient3> {
        unsafe {
            let k: IAudioClient3 = aygit.Activate(CLSCTX_ALL, None).ok()?;
            let (mut v, mut t, mut en_az, mut en_cok) = (0u32, 0u32, 0u32, 0u32);
            k.GetSharedModeEnginePeriod(bicim, &mut v, &mut t, &mut en_az, &mut en_cok).ok()?;
            if en_az == 0 || en_az >= v {
                return None;
            }
            match k.InitializeSharedAudioStream(0, en_az, bicim, None) {
                Ok(()) => {
                    k.Start().ok()?;
                    let hiz = (*bicim).nSamplesPerSec.max(1);
                    gunluk!("düşük gecikme: motor periyodu {} → {} kare ({:.1} ms)", v, en_az, en_az as f32 * 1000.0 / hiz as f32);
                    Some(k)
                }
                Err(e) => {
                    gunluk!("düşük gecikme açılamadı (önemsiz): {}", e);
                    None
                }
            }
        }
    }
}
