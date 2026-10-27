//! Telefonla konuşulan dil. Ayrıntı: PLAN.md "Protokol (v1)".
//! ⚠️ iPhone tarafındaki karşılığı ios/Cekirdek/Sources/Cekirdek/Paket.swift — ikisi birlikte değişir.
//!    Ortak altın örnek: `altin_baslik` testi ve Swift'teki `testAltinBaslik` aynı baytları bekler.

use serde::{Deserialize, Serialize};

pub const PORT: u16 = 47800;
pub const SURUM: u32 = 1;
pub const SERVIS: &str = "_syncpods._tcp.local.";
pub const BASLIK: usize = 24;
/// Paket başına kare (48 kHz'de 3,3 ms). Yedekli paket 24 + 2×640 = 1304 bayt, MTU'ya sığar.
pub const KARE: usize = 160;
pub const YEDEK_VAR: u16 = 1;
pub const BICIM_S16: u8 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Tur {
    Ses = 1,
    Sessizlik = 2,
    Mikrofon = 3,
    Punch = 4,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Baslik {
    pub tur: Tur,
    pub bayrak: u16,
    pub oturum: u32,
    pub sira: u32,
    pub konum: u32,
    pub kare: u16,
    pub kanal: u8,
    pub bicim: u8,
    pub hiz: u32,
}

impl Baslik {
    pub fn yaz(&self, b: &mut Vec<u8>) {
        b.push(b'S');
        b.push(self.tur as u8);
        b.extend_from_slice(&self.bayrak.to_le_bytes());
        b.extend_from_slice(&self.oturum.to_le_bytes());
        b.extend_from_slice(&self.sira.to_le_bytes());
        b.extend_from_slice(&self.konum.to_le_bytes());
        b.extend_from_slice(&self.kare.to_le_bytes());
        b.push(self.kanal);
        b.push(self.bicim);
        b.extend_from_slice(&self.hiz.to_le_bytes());
    }

    pub fn oku(b: &[u8]) -> Option<Baslik> {
        if b.len() < BASLIK || b[0] != b'S' {
            return None;
        }
        let u16_ = |i: usize| u16::from_le_bytes([b[i], b[i + 1]]);
        let u32_ = |i: usize| u32::from_le_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]]);
        let tur = match b[1] {
            1 => Tur::Ses,
            2 => Tur::Sessizlik,
            3 => Tur::Mikrofon,
            4 => Tur::Punch,
            _ => return None,
        };
        Some(Baslik {
            tur,
            bayrak: u16_(2),
            oturum: u32_(4),
            sira: u32_(8),
            konum: u32_(12),
            kare: u16_(16),
            kanal: b[18],
            bicim: b[19],
            hiz: u32_(20),
        })
    }
}

/// Denetim kanalı (TCP, satır başına bir JSON).
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(tag = "t", rename_all = "lowercase")]
pub enum Mesaj {
    // telefon → PC
    Hello { v: u32, id: String, name: String },
    Focus { phone: bool },
    Settings {
        #[serde(rename = "pauseMedia")]
        pause_media: bool,
        /// Bağlıyken PC'nin kendi çıkışı sussun (eski telefon sürümü göndermezse dokunulmaz).
        #[serde(rename = "muteLocal", default, skip_serializing_if = "Option::is_none")]
        mute_local: Option<bool>,
    },
    Mic { on: bool },
    Ping { ts: u64 },
    Bye,
    // PC → telefon
    Welcome { v: u32, pc: String, id: String, session: u32, udp: u16 },
    Wait,
    Denied,
    Status {
        playing: bool,
        device: String,
        title: Option<String>,
        artist: Option<String>,
        app: Option<String>,
        #[serde(rename = "pauseMedia")]
        pause_media: bool,
        #[serde(rename = "muteLocal")]
        mute_local: bool,
    },
    #[serde(rename = "micstate")]
    MicState { state: String },
    Pong { ts: u64 },
}

#[cfg(test)]
mod testler {
    use super::*;

    #[test]
    fn altin_baslik() {
        let b = Baslik { tur: Tur::Ses, bayrak: 1, oturum: 0x01020304, sira: 7, konum: 1120, kare: 160, kanal: 2, bicim: 1, hiz: 48000 };
        let mut v = Vec::new();
        b.yaz(&mut v);
        let hex: String = v.iter().map(|x| format!("{:02x}", x)).collect();
        assert_eq!(hex, "53010100040302010700000060040000a000020180bb0000");
        assert_eq!(Baslik::oku(&v), Some(b));
    }

    #[test]
    fn mesaj_json() {
        let m: Mesaj = serde_json::from_str(r#"{"t":"hello","v":1,"id":"abc","name":"Efe’nin iPhone’u"}"#).unwrap();
        assert_eq!(m, Mesaj::Hello { v: 1, id: "abc".into(), name: "Efe’nin iPhone’u".into() });
        let s = serde_json::to_string(&Mesaj::MicState { state: "noDevice".into() }).unwrap();
        assert_eq!(s, r#"{"t":"micstate","state":"noDevice"}"#);
        let s = serde_json::to_string(&Mesaj::Settings { pause_media: true, mute_local: None }).unwrap();
        assert_eq!(s, r#"{"t":"settings","pauseMedia":true}"#);
        let m: Mesaj = serde_json::from_str(r#"{"t":"settings","pauseMedia":false,"muteLocal":true}"#).unwrap();
        assert_eq!(m, Mesaj::Settings { pause_media: false, mute_local: Some(true) });
    }
}
