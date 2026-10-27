//! İş parçacıkları arasında paylaşılan durum.

use crate::ayarlar::Ayarlar;
use crate::mikrofon::MikTampon;
use crate::protokol::Mesaj;
use std::io::Write;
use std::net::{SocketAddr, TcpStream, UdpSocket};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Mutex;

#[derive(Default, Clone, Debug)]
pub struct Durum {
    pub telefon: Option<String>,
    pub caliyor: bool,
    pub cihaz: String,
    pub odak_telefonda: bool,
    pub baslik: Option<String>,
    pub sanatci: Option<String>,
    pub uygulama: Option<String>,
    pub mik: String,
}

pub enum MedyaIstek {
    /// true: telefon sesi devraldı → çalanı duraklat; false: geri ver → duraklattığımızı sürdür.
    Odak(bool),
    Kapat,
}

pub struct Ortak {
    pub ayarlar: Mutex<Ayarlar>,
    /// Geçerli telefon oturumu; 0 = bağlı telefon yok.
    pub oturum: AtomicU32,
    /// Ses yakalansın mı (telefon bağlı + UDP adresi biliniyor).
    pub aktif: AtomicBool,
    pub telefon_udp: Mutex<Option<SocketAddr>>,
    pub udp: UdpSocket,
    pub yazici: Mutex<Option<TcpStream>>,
    pub durum: Mutex<Durum>,
    pub medya: Mutex<Option<Sender<MedyaIstek>>>,
    pub mik: Mutex<MikTampon>,
    pub mik_acik: AtomicBool,
    /// Telefonun son bildirdiği durum ("phone" mesajı: ayarlar, rota, odak, ölçümler). Panel bunu gösterir.
    pub telefon: Mutex<Option<serde_json::Value>>,
    /// Telefonda kulaklık takılı mı. AirPods kutuya girince false: PC kendi sesini geri açar, yayın durur.
    pub kulaklik: AtomicBool,
    pub onay: Box<dyn Fn(&str) -> bool + Send + Sync>,
}

impl Ortak {
    pub fn gonder(&self, m: &Mesaj) {
        let mut y = self.yazici.lock().unwrap();
        if let Some(s) = y.as_mut() {
            if let Ok(mut satir) = serde_json::to_string(m) {
                satir.push('\n');
                if s.write_all(satir.as_bytes()).is_err() {
                    let _ = s.shutdown(std::net::Shutdown::Both);
                    *y = None;
                }
            }
        }
    }

    pub fn durum_gonder(&self) {
        let d = self.durum.lock().unwrap().clone();
        let (pause, sus) = {
            let a = self.ayarlar.lock().unwrap();
            (a.medya_duraklat, a.pc_sesini_kapat)
        };
        self.gonder(&Mesaj::Status { playing: d.caliyor, device: d.cihaz, title: d.baslik, artist: d.sanatci, app: d.uygulama, pause_media: pause, mute_local: sus });
    }

    pub fn ses_gonder(&self, paket: &[u8]) {
        if !self.kulaklik.load(Ordering::Relaxed) {
            return;
        }
        if let Some(a) = *self.telefon_udp.lock().unwrap() {
            let _ = self.udp.send_to(paket, a);
        }
    }

    pub fn medya_iste(&self, i: MedyaIstek) {
        if let Some(tx) = self.medya.lock().unwrap().as_ref() {
            let _ = tx.send(i);
        }
    }

    pub fn bagli(&self) -> bool {
        self.oturum.load(Ordering::Relaxed) != 0
    }
}
