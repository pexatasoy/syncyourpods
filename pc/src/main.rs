//! SyncYourPods — Windows tarafı. PC sesini aynı ağdaki iPhone'a, oradan AirPods'a taşır.
//! Ayrıntılar: ../PLAN.md

#![cfg_attr(windows, windows_subsystem = "windows")]

mod ayarlar;
mod kesif;
mod medya;
mod mikrofon;
mod ortak;
mod paket;
mod protokol;
mod sunucu;
#[cfg(windows)]
mod panel;
#[cfg(windows)]
mod tepsi;
mod yakala;

use ortak::{Durum, Ortak};
use std::net::{TcpListener, UdpSocket};
use std::sync::atomic::{AtomicBool, AtomicU32};
use std::sync::{Arc, Mutex};

fn main() {
    #[cfg(windows)]
    if !tepsi::tek_ornek() {
        return;
    }
    // Önceki oturum çökmüş ve PC'yi sessiz bırakmışsa önce onu düzelt.
    #[cfg(windows)]
    yakala::win::kurtar();
    let a = ayarlar::Ayarlar::yukle();
    let (pc_adi, pc_id) = (ayarlar::pc_adi(), a.pc_id.clone());
    gunluk!("SyncYourPods {} başlıyor — {}", env!("CARGO_PKG_VERSION"), pc_adi);

    // Linux yalnız deneme içindir: dışarıya açılmasın.
    #[cfg(windows)]
    let dinle = "0.0.0.0";
    #[cfg(not(windows))]
    let dinle = "127.0.0.1";
    let (tcp, udp) = match (TcpListener::bind((dinle, protokol::PORT)), UdpSocket::bind((dinle, protokol::PORT))) {
        (Ok(t), Ok(u)) => (t, u),
        (t, u) => {
            let hata = format!("{:?} {:?}", t.err(), u.err());
            gunluk!("port {} açılamadı: {}", protokol::PORT, hata);
            #[cfg(windows)]
            tepsi::uyari(&format!("SyncYourPods {} numaralı portu açamadı. Başka bir program kullanıyor olabilir.", protokol::PORT));
            return;
        }
    };

    #[cfg(windows)]
    let onay: Box<dyn Fn(&str) -> bool + Send + Sync> = Box::new(tepsi::onay_sor);
    #[cfg(not(windows))]
    let onay: Box<dyn Fn(&str) -> bool + Send + Sync> = Box::new(|_| true);

    let o = Arc::new(Ortak {
        ayarlar: Mutex::new(a),
        oturum: AtomicU32::new(0),
        aktif: AtomicBool::new(false),
        telefon_udp: Mutex::new(None),
        udp,
        yazici: Mutex::new(None),
        durum: Mutex::new(Durum { mik: "off".into(), ..Default::default() }),
        medya: Mutex::new(None),
        mik: Mutex::new(Default::default()),
        mik_acik: AtomicBool::new(false),
        telefon: Mutex::new(None),
        kulaklik: AtomicBool::new(true),
        onay,
    });

    {
        let o = o.clone();
        std::thread::spawn(move || sunucu::tcp_dinle(o, tcp));
    }
    {
        let o = o.clone();
        std::thread::spawn(move || sunucu::udp_dinle(o));
    }
    {
        let o = o.clone();
        std::thread::spawn(move || yakala::calistir(o));
    }
    medya::baslat(o.clone());
    #[cfg(windows)]
    let mdns = kesif::yayinla(&pc_adi, &pc_id);
    #[cfg(not(windows))]
    let mdns = std::env::var_os("SYP_MDNS").and_then(|_| kesif::yayinla(&pc_adi, &pc_id));

    #[cfg(windows)]
    panel::calistir(o.clone());
    #[cfg(not(windows))]
    loop {
        std::thread::sleep(std::time::Duration::from_secs(3600));
    }

    #[allow(unreachable_code)]
    if let Some(d) = mdns {
        let _ = d.shutdown();
    }
}
