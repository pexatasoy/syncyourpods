//! Kalıcı ayarlar: %APPDATA%\SyncYourPods\ayarlar.json (Linux'ta deneme için ~/.config/syncyourpods).

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Cihaz {
    pub id: String,
    pub ad: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default)]
pub struct Ayarlar {
    pub pc_id: String,
    pub guvenilen: Vec<Cihaz>,
    /// Telefon sesi devralınca PC'deki medyayı duraklat, bitince devam ettir.
    pub medya_duraklat: bool,
    /// Telefon bağlıyken bu PC'nin hoparlörünü sustur (deneysel: bazı ses kartlarında yakalanan sesi de susturur).
    pub hoparlor_sustur: bool,
}

impl Default for Ayarlar {
    fn default() -> Self {
        Ayarlar { pc_id: yeni_kimlik(), guvenilen: Vec::new(), medya_duraklat: true, hoparlor_sustur: false }
    }
}

pub fn klasor() -> PathBuf {
    #[cfg(windows)]
    let kok = std::env::var_os("APPDATA").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
    #[cfg(not(windows))]
    let kok = std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")).unwrap_or_else(|| PathBuf::from("."));
    let k = kok.join("SyncYourPods");
    let _ = std::fs::create_dir_all(&k);
    k
}

impl Ayarlar {
    pub fn yukle() -> Ayarlar {
        let yol = klasor().join("ayarlar.json");
        let a = std::fs::read_to_string(&yol).ok().and_then(|s| serde_json::from_str::<Ayarlar>(&s).ok()).unwrap_or_default();
        a.kaydet();
        a
    }

    pub fn kaydet(&self) {
        let yol = klasor().join("ayarlar.json");
        let gecici = yol.with_extension("json.tmp");
        if let Ok(s) = serde_json::to_string_pretty(self) {
            if std::fs::write(&gecici, s).is_ok() {
                let _ = std::fs::rename(&gecici, &yol);
            }
        }
    }

    pub fn guvenilir_mi(&self, id: &str) -> bool {
        self.guvenilen.iter().any(|c| c.id == id)
    }
}

pub fn yeni_kimlik() -> String {
    let n = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let p = std::process::id() as u128;
    format!("{:016x}", (n ^ (p << 64) ^ (n >> 17)) as u64)
}

pub fn rastgele_u32() -> u32 {
    let n = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(1);
    let mut x = (n as u64) ^ ((n >> 64) as u64) ^ 0x9E37_79B9_7F4A_7C15;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    (x as u32).max(1)
}

/// Bilgisayarın görünen adı.
pub fn pc_adi() -> String {
    #[cfg(windows)]
    if let Ok(a) = std::env::var("COMPUTERNAME") {
        return a;
    }
    std::fs::read_to_string("/etc/hostname").map(|s| s.trim().to_string()).unwrap_or_else(|_| "PC".into())
}

/// Küçük günlük dosyası (Windows'ta konsol yok). 512 KB'ı geçince baştan başlar.
pub fn gunluk(metin: &str) {
    use std::io::Write;
    let yol = klasor().join("gunluk.txt");
    if std::fs::metadata(&yol).map(|m| m.len() > 512 * 1024).unwrap_or(false) {
        let _ = std::fs::remove_file(&yol);
    }
    let zaman = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&yol) {
        let _ = writeln!(f, "{} {}", zaman, metin);
    }
    #[cfg(not(windows))]
    eprintln!("{}", metin);
}

#[macro_export]
macro_rules! gunluk {
    ($($a:tt)*) => { $crate::ayarlar::gunluk(&format!($($a)*)) };
}
