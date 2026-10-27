//! PC'de ne çaldığını okur (Windows'un medya denetimi: tarayıcı, Spotify, VLC…)
//! ve telefon sesi devralınca çalanı duraklatır, geri verince yalnız KENDİ duraklattığını sürdürür.

use crate::ortak::{MedyaIstek, Ortak};
use std::sync::mpsc::{channel, RecvTimeoutError};
use std::sync::Arc;
use std::time::Duration;

pub fn baslat(o: Arc<Ortak>) {
    let (tx, rx) = channel::<MedyaIstek>();
    *o.medya.lock().unwrap() = Some(tx);
    std::thread::spawn(move || {
        #[cfg(windows)]
        unsafe {
            let _ = windows::Win32::System::Com::CoInitializeEx(None, windows::Win32::System::Com::COINIT_MULTITHREADED);
        }
        let mut duraklatilan: Option<String> = None;
        loop {
            match rx.recv_timeout(Duration::from_secs(1)) {
                Ok(MedyaIstek::Odak(telefon)) => {
                    let duraklat = o.ayarlar.lock().unwrap().medya_duraklat;
                    if telefon && duraklat {
                        if duraklatilan.is_none() {
                            duraklatilan = platform::duraklat();
                        }
                    } else if !telefon {
                        if let Some(id) = duraklatilan.take() {
                            platform::surdur(&id);
                        }
                    }
                }
                Ok(MedyaIstek::Kapat) => return,
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return,
            }
            if o.bagli() {
                let simdi = platform::simdi_calan();
                let degisti = {
                    let mut d = o.durum.lock().unwrap();
                    let (b, s, u) = simdi.unwrap_or_default();
                    let yeni = (Some(b).filter(|x| !x.is_empty()), Some(s).filter(|x| !x.is_empty()), Some(u).filter(|x| !x.is_empty()));
                    let x = (d.baslik.clone(), d.sanatci.clone(), d.uygulama.clone()) != yeni;
                    (d.baslik, d.sanatci, d.uygulama) = yeni;
                    x
                };
                if degisti {
                    o.durum_gonder();
                }
            }
        }
    });
}

/// "Chrome", "Spotify.exe", "308046B0AF4A39CB" (Edge PWA) gibi kimlikleri okunur ada çevirir.
pub fn uygulama_adi(kimlik: &str) -> String {
    let son = kimlik.rsplit(['\\', '!']).next().unwrap_or(kimlik);
    let son = son.trim_end_matches(".exe").trim_end_matches(".EXE");
    let k = son.to_lowercase();
    let bilinen = [
        ("chrome", "Chrome"),
        ("msedge", "Edge"),
        ("firefox", "Firefox"),
        ("spotify", "Spotify"),
        ("vlc", "VLC"),
        ("brave", "Brave"),
        ("opera", "Opera"),
        ("zune", "Medya Oynatıcı"),
        ("music", "Müzik"),
        ("discord", "Discord"),
    ];
    for (a, b) in bilinen {
        if k.contains(a) {
            return b.into();
        }
    }
    son.into()
}

#[cfg(windows)]
mod platform {
    use windows::Media::Control::*;

    fn yonetici() -> windows::core::Result<GlobalSystemMediaTransportControlsSessionManager> {
        GlobalSystemMediaTransportControlsSessionManager::RequestAsync()?.join()
    }

    pub fn duraklat() -> Option<String> {
        let m = yonetici().ok()?;
        let s = m.GetCurrentSession().ok()?;
        let durum = s.GetPlaybackInfo().ok()?.PlaybackStatus().ok()?;
        if durum != GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing {
            return None;
        }
        let id = s.SourceAppUserModelId().ok()?.to_string();
        s.TryPauseAsync().ok()?.join().ok()?;
        crate::gunluk!("PC medyası duraklatıldı: {}", id);
        Some(id)
    }

    pub fn surdur(id: &str) {
        let Ok(m) = yonetici() else { return };
        let Ok(liste) = m.GetSessions() else { return };
        for s in liste {
            if s.SourceAppUserModelId().map(|x| x.to_string() == id).unwrap_or(false) {
                let paused = s
                    .GetPlaybackInfo()
                    .and_then(|i| i.PlaybackStatus())
                    .map(|d| d == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Paused)
                    .unwrap_or(false);
                // Kullanıcı bu arada kendisi başlattı/kapattıysa dokunma.
                if paused {
                    let _ = s.TryPlayAsync().and_then(|a| a.join());
                    crate::gunluk!("PC medyası sürdürüldü: {}", id);
                }
                return;
            }
        }
    }

    pub fn simdi_calan() -> Option<(String, String, String)> {
        let m = yonetici().ok()?;
        let s = m.GetCurrentSession().ok()?;
        let p = s.TryGetMediaPropertiesAsync().ok()?.join().ok()?;
        let app = super::uygulama_adi(&s.SourceAppUserModelId().ok()?.to_string());
        Some((p.Title().ok()?.to_string(), p.Artist().map(|a| a.to_string()).unwrap_or_default(), app))
    }
}

#[cfg(not(windows))]
mod platform {
    pub fn duraklat() -> Option<String> {
        crate::gunluk!("(deneme) PC medyası duraklatıldı");
        Some("deneme".into())
    }
    pub fn surdur(_id: &str) {
        crate::gunluk!("(deneme) PC medyası sürdürüldü");
    }
    pub fn simdi_calan() -> Option<(String, String, String)> {
        Some(("Deneme sinyali".into(), "440 Hz".into(), "SyncYourPods".into()))
    }
}

#[cfg(test)]
mod testler {
    use super::uygulama_adi;
    #[test]
    fn adlar() {
        assert_eq!(uygulama_adi("Chrome"), "Chrome");
        assert_eq!(uygulama_adi("Spotify.exe"), "Spotify");
        assert_eq!(uygulama_adi("C:\\Program Files\\VideoLAN\\VLC\\vlc.exe"), "VLC");
        assert_eq!(uygulama_adi("Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic"), "Medya Oynatıcı");
    }
}
