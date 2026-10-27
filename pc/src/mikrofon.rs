//! AirPods mikrofonu → PC. Telefon mono s16 yollar; PC bunu VB-CABLE'ın "CABLE Input" aygıtına çalar,
//! uygulamalar (Discord, Zoom…) mikrofon olarak "CABLE Output"u seçer.
//! VB-CABLE yoksa telefona "noDevice" döner, telefon kurulum adımını gösterir.

use crate::gunluk;
use crate::ortak::Ortak;
use crate::protokol::Mesaj;
use std::collections::VecDeque;
use std::sync::atomic::Ordering;
use std::sync::Arc;

/// Mikrofon tamponu: telefon hızında mono örnekler. Çalıcı aygıt hızına kendisi çevirir.
pub struct MikTampon {
    pub hiz: u32,
    pub ornek: VecDeque<f32>,
    son_sira: Option<u32>,
    pub doldu: bool,
}

impl Default for MikTampon {
    fn default() -> Self {
        MikTampon { hiz: 48000, ornek: VecDeque::with_capacity(48000), son_sira: None, doldu: false }
    }
}

impl MikTampon {
    pub fn besle(&mut self, hiz: u32, sira: u32, ornek: &[f32]) {
        if hiz != self.hiz {
            self.hiz = hiz;
            self.ornek.clear();
            self.doldu = false;
        }
        if let Some(s) = self.son_sira {
            // Geç gelen/kopya paket: at. Kayıpta araya sessizlik koymuyoruz (konuşmada kısa boşluk daha az rahatsız eder).
            if sira.wrapping_sub(s) > u32::MAX / 2 || sira == s {
                return;
            }
        }
        self.son_sira = Some(sira);
        self.ornek.extend(ornek.iter().copied());
        // 250 ms'den fazla birikirse gecikme büyümesin: eskiyi at.
        let azami = self.hiz as usize / 4;
        while self.ornek.len() > azami {
            self.ornek.pop_front();
        }
        // 40 ms birikince çalmaya başla.
        if self.ornek.len() >= self.hiz as usize / 25 {
            self.doldu = true;
        }
    }

    /// `n` kareyi `hedef_hiz`'da üretir (doğrusal ara değerleme). Tampon boşalırsa sessizlik.
    pub fn cek(&mut self, n: usize, hedef_hiz: u32, konum: &mut f64, cikti: &mut Vec<f32>) {
        cikti.clear();
        if !self.doldu {
            cikti.resize(n, 0.0);
            return;
        }
        let adim = self.hiz as f64 / hedef_hiz as f64;
        for _ in 0..n {
            let i = *konum as usize;
            if i + 1 >= self.ornek.len() {
                self.doldu = false;
                cikti.resize(n, 0.0);
                return;
            }
            let k = (*konum - i as f64) as f32;
            cikti.push(self.ornek[i] * (1.0 - k) + self.ornek[i + 1] * k);
            *konum += adim;
        }
        let tuketilen = *konum as usize;
        self.ornek.drain(..tuketilen.min(self.ornek.len()));
        *konum -= tuketilen as f64;
    }
}

pub fn ayarla(o: &Arc<Ortak>, ac: bool) {
    let onceki = o.mik_acik.swap(ac, Ordering::SeqCst);
    if ac && !onceki {
        *o.mik.lock().unwrap() = MikTampon::default();
        let o2 = o.clone();
        std::thread::spawn(move || {
            let durum = calistir(&o2);
            o2.mik_acik.store(false, Ordering::SeqCst);
            o2.durum.lock().unwrap().mik = durum.into();
            o2.gonder(&Mesaj::MicState { state: durum.into() });
        });
    } else if !ac && onceki {
        o.durum.lock().unwrap().mik = "off".into();
        o.gonder(&Mesaj::MicState { state: "off".into() });
    }
}

/// Mikrofon kapanana kadar çalar. Dönüş: son durum ("off" | "noDevice" | "error").
#[cfg(windows)]
fn calistir(o: &Arc<Ortak>) -> &'static str {
    match unsafe { win::cal(o) } {
        Ok(d) => d,
        Err(e) => {
            gunluk!("mikrofon hatası: {}", e);
            "error"
        }
    }
}

#[cfg(not(windows))]
fn calistir(o: &Arc<Ortak>) -> &'static str {
    // Linux'ta deneme: tamponu tüket, aygıt yok say.
    o.gonder(&Mesaj::MicState { state: "on".into() });
    while o.mik_acik.load(Ordering::SeqCst) {
        std::thread::sleep(std::time::Duration::from_millis(20));
        let mut c = Vec::new();
        let mut k = 0.0;
        o.mik.lock().unwrap().cek(960, 48000, &mut k, &mut c);
    }
    "off"
}

#[cfg(windows)]
mod win {
    use super::*;
    use crate::yakala::win::{aygit_adi, bicim_oku, Bicim};
    use windows::Win32::Media::Audio::*;
    use windows::Win32::System::Com::*;
    use windows::Win32::System::Threading::*;

    pub unsafe fn cal(o: &Arc<Ortak>) -> windows::core::Result<&'static str> {
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            let numara: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
            let liste = numara.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)?;
            let mut hedef = None;
            for i in 0..liste.GetCount()? {
                let c = liste.Item(i)?;
                let ad = aygit_adi(&c);
                if ad.to_lowercase().contains("cable input") {
                    hedef = Some((c, ad));
                    break;
                }
            }
            let Some((aygit, ad)) = hedef else {
                gunluk!("mikrofon: CABLE Input bulunamadı");
                return Ok("noDevice");
            };
            gunluk!("mikrofon aygıtı: {}", ad);
            let istemci: IAudioClient = aygit.Activate(CLSCTX_ALL, None)?;
            let bicim_p = istemci.GetMixFormat()?;
            let bicim = bicim_oku(bicim_p);
            istemci.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK, 200_000, 0, bicim_p, None)?;
            let olay = CreateEventW(None, false, false, None)?;
            istemci.SetEventHandle(olay)?;
            let tampon_kare = istemci.GetBufferSize()?;
            let calici: IAudioRenderClient = istemci.GetService()?;
            istemci.Start()?;
            o.durum.lock().unwrap().mik = "on".into();
            o.gonder(&Mesaj::MicState { state: "on".into() });
            let mut konum = 0.0f64;
            let mut mono = Vec::new();
            while o.mik_acik.load(Ordering::SeqCst) && o.bagli() {
                WaitForSingleObject(olay, 50);
                let dolu = istemci.GetCurrentPadding()?;
                let bos = (tampon_kare - dolu) as usize;
                if bos == 0 {
                    continue;
                }
                o.mik.lock().unwrap().cek(bos, bicim.hiz, &mut konum, &mut mono);
                let p = calici.GetBuffer(bos as u32)?;
                yaz_cikti(p, &bicim, &mono);
                calici.ReleaseBuffer(bos as u32, 0)?;
            }
            let _ = istemci.Stop();
            CoTaskMemFree(Some(bicim_p as *const _));
            Ok("off")
        }
    }

    unsafe fn yaz_cikti(p: *mut u8, b: &Bicim, mono: &[f32]) {
        unsafe {
            let k = b.kanal;
            if b.float {
                let d = std::slice::from_raw_parts_mut(p as *mut f32, mono.len() * k);
                for (i, s) in mono.iter().enumerate() {
                    for c in 0..k {
                        d[i * k + c] = *s;
                    }
                }
            } else if b.bit == 16 {
                let d = std::slice::from_raw_parts_mut(p as *mut i16, mono.len() * k);
                for (i, s) in mono.iter().enumerate() {
                    for c in 0..k {
                        d[i * k + c] = (s.clamp(-1.0, 1.0) * 32767.0) as i16;
                    }
                }
            } else if b.bit == 32 {
                let d = std::slice::from_raw_parts_mut(p as *mut i32, mono.len() * k);
                for (i, s) in mono.iter().enumerate() {
                    for c in 0..k {
                        d[i * k + c] = (s.clamp(-1.0, 1.0) as f64 * 2147483647.0) as i32;
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod testler {
    use super::*;

    #[test]
    fn hiz_cevirme() {
        let mut t = MikTampon::default();
        let girdi: Vec<f32> = (0..2400).map(|i| (i as f32 / 2400.0)).collect();
        t.besle(24000, 0, &girdi);
        let mut k = 0.0;
        let mut c = Vec::new();
        t.cek(960, 48000, &mut k, &mut c);
        assert_eq!(c.len(), 960);
        // 24k → 48k: her girdi örneği iki çıktı örneği
        assert!((c[2] - girdi[1]).abs() < 1e-6);
        assert_eq!(t.ornek.len(), 2400 - 480);
    }
}
