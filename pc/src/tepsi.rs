//! Windows yardımcıları: tek kopya, uyarı/onay pencereleri, açılışta başlatma, tepsi simgesi çizimi.
//! Tepsi ve panel döngüsü panel.rs'te.

use tray_icon::Icon;
use windows::core::{w, HSTRING};
use windows::Win32::Foundation::{GetLastError, ERROR_ALREADY_EXISTS, ERROR_SUCCESS};
use windows::Win32::System::Registry::*;
use windows::Win32::System::Threading::CreateMutexW;
use windows::Win32::UI::WindowsAndMessaging::*;

const ACILIS_ANAHTARI: &str = "Software\\Microsoft\\Windows\\CurrentVersion\\Run";
const ACILIS_DEGERI: &str = "SyncYourPods";

/// İkinci kopya açılırsa sessizce çıkar (port zaten dolu olurdu).
pub fn tek_ornek() -> bool {
    unsafe {
        let _ = CreateMutexW(None, true, w!("Local\\SyncYourPods.TekOrnek"));
        GetLastError() != ERROR_ALREADY_EXISTS
    }
}

pub fn uyari(metin: &str) {
    unsafe {
        MessageBoxW(None, &HSTRING::from(metin), w!("SyncYourPods"), MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
    }
}

/// Yeni iPhone ilk kez bağlanırken sorulur. Cevap kalıcıdır.
pub fn onay_sor(telefon: &str) -> bool {
    let metin = if crate::dil::turkce() {
        format!("“{}” bu bilgisayarın sesini AirPods’a aktarmak istiyor.\n\nİzin verilsin mi?", telefon)
    } else {
        format!("“{}” wants to play this computer's sound on its AirPods.\n\nAllow it?", telefon)
    };
    unsafe {
        MessageBoxW(None, &HSTRING::from(metin), w!("SyncYourPods"), MB_YESNO | MB_ICONQUESTION | MB_SETFOREGROUND | MB_TOPMOST) == IDYES
    }
}

pub fn acilista_mi() -> bool {
    unsafe { RegGetValueW(HKEY_CURRENT_USER, &HSTRING::from(ACILIS_ANAHTARI), &HSTRING::from(ACILIS_DEGERI), RRF_RT_REG_SZ, None, None, None) == ERROR_SUCCESS }
}

pub fn acilis_ayarla(ac: bool) {
    unsafe {
        if ac {
            let Ok(yol) = std::env::current_exe() else { return };
            let deger: Vec<u16> = format!("\"{}\"", yol.display()).encode_utf16().chain(std::iter::once(0)).collect();
            let _ = RegSetKeyValueW(
                HKEY_CURRENT_USER,
                &HSTRING::from(ACILIS_ANAHTARI),
                &HSTRING::from(ACILIS_DEGERI),
                REG_SZ.0,
                Some(deger.as_ptr() as *const _),
                (deger.len() * 2) as u32,
            );
        } else {
            let _ = RegDeleteKeyValueW(HKEY_CURRENT_USER, &HSTRING::from(ACILIS_ANAHTARI), &HSTRING::from(ACILIS_DEGERI));
        }
    }
}

/// 32×32 simge: halka + nokta. Bekliyorken gri, bağlıyken beyaz halka + mavi nokta.
pub fn simge(bagli: bool, telefonda: bool) -> Icon {
    let n = 32usize;
    let mut p = vec![0u8; n * n * 4];
    let (halka, nokta): ([u8; 3], [u8; 3]) = if !bagli {
        ([150, 150, 150], [150, 150, 150])
    } else if telefonda {
        ([255, 255, 255], [255, 159, 10])
    } else {
        ([255, 255, 255], [10, 132, 255])
    };
    let m = (n as f32 - 1.0) / 2.0;
    for y in 0..n {
        for x in 0..n {
            let d = ((x as f32 - m).powi(2) + (y as f32 - m).powi(2)).sqrt();
            // Kenar yumuşatma: mesafeye göre saydamlık.
            let h = (1.6 - (d - 12.5).abs()).clamp(0.0, 1.0);
            let k = (5.5 - d + 0.5).clamp(0.0, 1.0);
            let (renk, a) = if k > 0.0 { (nokta, k) } else { (halka, h) };
            let i = (y * n + x) * 4;
            p[i..i + 3].copy_from_slice(&renk);
            p[i + 3] = (a * 255.0) as u8;
        }
    }
    Icon::from_rgba(p, n as u32, n as u32).expect("simge")
}
