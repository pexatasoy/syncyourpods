//! Denetim kanalı (TCP) ve telefondan gelen UDP (punch + mikrofon).
//! Aynı anda tek telefon: yeni gelen eskisinin yerini alır.

use crate::ayarlar::{rastgele_u32, Cihaz};
use crate::gunluk;
use crate::ortak::{MedyaIstek, Ortak};
use crate::protokol::*;
use std::io::{BufRead, BufReader};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

pub fn tcp_dinle(o: Arc<Ortak>, dinleyici: TcpListener) {
    for gelen in dinleyici.incoming() {
        match gelen {
            Ok(s) => {
                let o = o.clone();
                std::thread::spawn(move || {
                    let adres = s.peer_addr().map(|a| a.to_string()).unwrap_or_default();
                    if let Err(e) = istemci(o, s) {
                        gunluk!("bağlantı bitti {}: {}", adres, e);
                    }
                });
            }
            Err(e) => gunluk!("tcp kabul hatası: {}", e),
        }
    }
}

fn istemci(o: Arc<Ortak>, s: TcpStream) -> std::io::Result<()> {
    s.set_nodelay(true)?;
    // Telefon 2 sn'de bir ping atar; 7 sn ses yoksa bağlantı ölmüş sayılır.
    s.set_read_timeout(Some(Duration::from_secs(7)))?;
    let okuyucu = BufReader::new(s.try_clone()?);
    let mut benim_oturum = 0u32;
    let sonuc = (|| -> std::io::Result<()> {
        for satir in okuyucu.lines() {
            let satir = satir?;
            let m: Mesaj = match serde_json::from_str(&satir) {
                Ok(m) => m,
                Err(_) => continue,
            };
            if benim_oturum == 0 {
                if let Mesaj::Hello { id, name, .. } = m {
                    benim_oturum = selamla(&o, &s, &id, &name)?;
                    if benim_oturum == 0 {
                        return Ok(());
                    }
                }
                continue;
            }
            if o.oturum.load(Ordering::SeqCst) != benim_oturum {
                return Ok(()); // başka telefon devraldı
            }
            match m {
                Mesaj::Focus { phone } => {
                    o.durum.lock().unwrap().odak_telefonda = phone;
                    o.medya_iste(MedyaIstek::Odak(phone));
                }
                Mesaj::Settings { pause_media } => {
                    let mut a = o.ayarlar.lock().unwrap();
                    a.medya_duraklat = pause_media;
                    a.kaydet();
                }
                Mesaj::Mic { on } => crate::mikrofon::ayarla(&o, on),
                Mesaj::Ping { ts } => o.gonder(&Mesaj::Pong { ts }),
                Mesaj::Bye => return Ok(()),
                _ => {}
            }
        }
        Ok(())
    })();
    if benim_oturum != 0 && o.oturum.compare_exchange(benim_oturum, 0, Ordering::SeqCst, Ordering::SeqCst).is_ok() {
        ayril(&o);
    }
    sonuc
}

/// Yeni telefonu karşılar. Güvenilir değilse PC'de onay sorar. Dönen oturum 0 ise reddedildi.
fn selamla(o: &Arc<Ortak>, s: &TcpStream, id: &str, ad: &str) -> std::io::Result<u32> {
    let guvenilir = o.ayarlar.lock().unwrap().guvenilir_mi(id);
    if !guvenilir {
        yaz(s, &Mesaj::Wait)?;
        // Onay penceresi beklerken telefon ping atmaz; zaman aşımını uzat.
        s.set_read_timeout(Some(Duration::from_secs(120)))?;
        let kabul = (o.onay)(ad);
        s.set_read_timeout(Some(Duration::from_secs(7)))?;
        if !kabul {
            yaz(s, &Mesaj::Denied)?;
            gunluk!("reddedildi: {}", ad);
            return Ok(0);
        }
        let mut a = o.ayarlar.lock().unwrap();
        a.guvenilen.retain(|c| c.id != id);
        a.guvenilen.push(Cihaz { id: id.into(), ad: ad.into() });
        a.kaydet();
    }
    let oturum = rastgele_u32();
    {
        let mut y = o.yazici.lock().unwrap();
        if let Some(eski) = y.take() {
            let _ = eski.shutdown(Shutdown::Both);
        }
        *y = Some(s.try_clone()?);
    }
    *o.telefon_udp.lock().unwrap() = None;
    o.oturum.store(oturum, Ordering::SeqCst);
    {
        let mut d = o.durum.lock().unwrap();
        d.telefon = Some(ad.into());
        d.odak_telefonda = false;
    }
    let (pc, pc_id) = (crate::ayarlar::pc_adi(), o.ayarlar.lock().unwrap().pc_id.clone());
    o.gonder(&Mesaj::Welcome { v: SURUM, pc, id: pc_id, session: oturum, udp: PORT });
    o.durum_gonder();
    gunluk!("bağlandı: {} (oturum {:08x})", ad, oturum);
    Ok(oturum)
}

fn ayril(o: &Arc<Ortak>) {
    o.aktif.store(false, Ordering::SeqCst);
    *o.telefon_udp.lock().unwrap() = None;
    *o.yazici.lock().unwrap() = None;
    crate::mikrofon::ayarla(o, false);
    // Telefon giderken PC medyasını duraklatılmış bırakmayalım.
    o.medya_iste(MedyaIstek::Odak(false));
    let mut d = o.durum.lock().unwrap();
    d.telefon = None;
    d.odak_telefonda = false;
    gunluk!("telefon ayrıldı");
}

fn yaz(s: &TcpStream, m: &Mesaj) -> std::io::Result<()> {
    use std::io::Write;
    let mut satir = serde_json::to_string(m).unwrap_or_default();
    satir.push('\n');
    (&*s).write_all(satir.as_bytes())
}

pub fn udp_dinle(o: Arc<Ortak>) {
    let mut tampon = vec![0u8; 2048];
    loop {
        let (n, adres) = match o.udp.recv_from(&mut tampon) {
            Ok(x) => x,
            // Windows'ta telefon kapanınca gelen ICMP "ulaşılamadı" bir sonraki okumada hata olarak döner; önemsiz.
            Err(_) => {
                std::thread::sleep(Duration::from_millis(2));
                continue;
            }
        };
        let Some(b) = Baslik::oku(&tampon[..n]) else { continue };
        let oturum = o.oturum.load(Ordering::SeqCst);
        if oturum == 0 || b.oturum != oturum {
            continue;
        }
        match b.tur {
            Tur::Punch => {
                let mut t = o.telefon_udp.lock().unwrap();
                if *t != Some(adres) {
                    gunluk!("telefon ses adresi: {}", adres);
                    *t = Some(adres);
                }
                o.aktif.store(true, Ordering::SeqCst);
            }
            Tur::Mikrofon => {
                let yuk = &tampon[BASLIK..n];
                let ornek: Vec<f32> = yuk.chunks_exact(2).map(|c| i16::from_le_bytes([c[0], c[1]]) as f32 / 32768.0).collect();
                o.mik.lock().unwrap().besle(b.hiz, b.sira, &ornek);
            }
            _ => {}
        }
    }
}
