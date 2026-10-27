//! Bonjour ile "_syncpods._tcp" yayını: iPhone PC'yi adres girmeden bulur.

use crate::gunluk;
use crate::protokol::{PORT, SERVIS, SURUM};
use mdns_sd::{ServiceDaemon, ServiceInfo};

pub fn yayinla(pc_adi: &str, pc_id: &str) -> Option<ServiceDaemon> {
    let d = match ServiceDaemon::new() {
        Ok(d) => d,
        Err(e) => {
            gunluk!("mdns başlatılamadı: {}", e);
            return None;
        }
    };
    // Bonjour ana makine adı: yalnız harf/rakam/tire.
    let makine: String = pc_adi.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
    let makine = format!("{}.local.", makine.trim_matches('-').to_lowercase());
    let surum = SURUM.to_string();
    let ozellik = [("v", surum.as_str()), ("id", pc_id), ("name", pc_adi)];
    match ServiceInfo::new(SERVIS, pc_adi, &makine, "", PORT, &ozellik[..]) {
        Ok(bilgi) => {
            if let Err(e) = d.register(bilgi.enable_addr_auto()) {
                gunluk!("mdns kaydı olmadı: {}", e);
            } else {
                gunluk!("ağda yayında: {} ({})", pc_adi, makine);
            }
        }
        Err(e) => gunluk!("mdns bilgisi kurulamadı: {}", e),
    }
    Some(d)
}
