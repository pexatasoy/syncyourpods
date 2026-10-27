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
    use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
    use windows::Win32::Media::Audio::*;
    use windows::Win32::Media::KernelStreaming::WAVE_FORMAT_EXTENSIBLE;
    use windows::Win32::Media::Multimedia::{KSDATAFORMAT_SUBTYPE_IEEE_FLOAT, WAVE_FORMAT_IEEE_FLOAT};
    use windows::Win32::System::Com::*;
    use windows::Win32::System::Threading::*;

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
                .unwrap_or_else(|_| "Ses aygıtı".into())
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

            // Deneysel: telefon bağlıyken PC hoparlörünü sustur, çıkarken eski hâline getir.
            let mut sesi_biz_kistik = false;
            let hacim: Option<IAudioEndpointVolume> = aygit.Activate(CLSCTX_ALL, None).ok();
            if o.ayarlar.lock().unwrap().hoparlor_sustur {
                if let Some(h) = &hacim {
                    if h.GetMute().map(|m| !m.as_bool()).unwrap_or(false) {
                        let _ = h.SetMute(true, std::ptr::null());
                        sesi_biz_kistik = true;
                    }
                }
            }

            let istemci: IAudioClient = aygit.Activate(CLSCTX_ALL, None)?;
            let bicim_p = istemci.GetMixFormat()?;
            let b = bicim_oku(bicim_p);
            gunluk!("yakalama: {} — {} Hz, {} kanal, {} bit{}", ad, b.hiz, b.kanal, b.bit, if b.float { " float" } else { "" });
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
            if sesi_biz_kistik {
                if let Some(h) = &hacim {
                    let _ = h.SetMute(false, std::ptr::null());
                }
            }
            sonuc
        }
    }
}
