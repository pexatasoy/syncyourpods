//! Yakalanan sesi 160 karelik paketlere böler. Her paket bir öncekini yedek olarak taşır:
//! tek paket kaybolursa telefon onu bir sonrakinden kurtarır.
//! Sessizlikte ses göndermez; 100 ms'de bir "sessizlik" paketi atar (telefon bunu kayıp sanmasın).

use crate::protokol::*;
use std::time::{Duration, Instant};

/// Bu kadar parça (≈100 ms) üst üste sessizse yayın durur.
const SESSIZ_ESIK: u32 = 30;
const SESSIZLIK_ARALIGI: Duration = Duration::from_millis(100);
/// |örnek| bunun altındaysa sessiz sayılır (dithering gürültüsü yayını açık tutmasın).
const SESSIZ_GENLIK: i16 = 4;

pub struct Paketleyici {
    pub hiz: u32,
    bekleyen: Vec<i16>,
    onceki: Option<Vec<u8>>,
    sira: u32,
    konum: u32,
    sessiz_sayac: u32,
    son_sessizlik: Option<Instant>,
    /// Son çalan parçanın zamanı — "PC'de ses var mı" bilgisi buradan.
    pub son_ses: Option<Instant>,
}

impl Paketleyici {
    pub fn yeni(hiz: u32) -> Self {
        Paketleyici { hiz, bekleyen: Vec::with_capacity(KARE * 8), onceki: None, sira: 0, konum: 0, sessiz_sayac: SESSIZ_ESIK, son_sessizlik: None, son_ses: None }
    }

    pub fn caliyor(&self) -> bool {
        self.son_ses.map(|t| t.elapsed() < Duration::from_millis(1500)).unwrap_or(false)
    }

    /// `ornekler`: araya girmiş stereo s16 (L R L R …).
    pub fn ekle(&mut self, ornekler: &[i16], oturum: u32, gonder: &mut dyn FnMut(&[u8])) {
        self.bekleyen.extend_from_slice(ornekler);
        let parca = KARE * 2;
        let mut bas = 0;
        while self.bekleyen.len() - bas >= parca {
            let p = &self.bekleyen[bas..bas + parca];
            bas += parca;
            let sessiz = p.iter().all(|s| s.unsigned_abs() <= SESSIZ_GENLIK as u16);
            if sessiz {
                self.sessiz_sayac = self.sessiz_sayac.saturating_add(1);
            } else {
                self.sessiz_sayac = 0;
                self.son_ses = Some(Instant::now());
            }
            if self.sessiz_sayac > SESSIZ_ESIK {
                self.konum = self.konum.wrapping_add(KARE as u32);
                self.onceki = None;
                Self::sessizlik_gonder(&mut self.son_sessizlik, self.sira, self.konum, self.hiz, oturum, gonder);
                continue;
            }
            let mut yuk = Vec::with_capacity(parca * 2);
            for s in p {
                yuk.extend_from_slice(&s.to_le_bytes());
            }
            let mut b = Vec::with_capacity(BASLIK + yuk.len() * 2);
            Baslik {
                tur: Tur::Ses,
                bayrak: if self.onceki.is_some() { YEDEK_VAR } else { 0 },
                oturum,
                sira: self.sira,
                konum: self.konum,
                kare: KARE as u16,
                kanal: 2,
                bicim: BICIM_S16,
                hiz: self.hiz,
            }
            .yaz(&mut b);
            b.extend_from_slice(&yuk);
            if let Some(o) = &self.onceki {
                b.extend_from_slice(o);
            }
            gonder(&b);
            self.sira = self.sira.wrapping_add(1);
            self.konum = self.konum.wrapping_add(KARE as u32);
            self.onceki = Some(yuk);
        }
        self.bekleyen.drain(..bas);
    }

    /// Ses aygıtı hiç veri vermediğinde (Windows sessizlikte olay üretmez) çağrılır.
    pub fn bos(&mut self, oturum: u32, gonder: &mut dyn FnMut(&[u8])) {
        self.sessiz_sayac = SESSIZ_ESIK + 1;
        self.onceki = None;
        self.bekleyen.clear();
        Self::sessizlik_gonder(&mut self.son_sessizlik, self.sira, self.konum, self.hiz, oturum, gonder);
    }

    fn sessizlik_gonder(son: &mut Option<Instant>, sira: u32, konum: u32, hiz: u32, oturum: u32, gonder: &mut dyn FnMut(&[u8])) {
        if son.map(|t| t.elapsed() < SESSIZLIK_ARALIGI).unwrap_or(false) {
            return;
        }
        *son = Some(Instant::now());
        let mut b = Vec::with_capacity(BASLIK);
        Baslik { tur: Tur::Sessizlik, bayrak: 0, oturum, sira, konum, kare: 0, kanal: 2, bicim: BICIM_S16, hiz }.yaz(&mut b);
        gonder(&b);
    }
}

/// Aygıtın karışım biçimindeki (çoğunlukla float32, 2+ kanal) sesi stereo s16'ya çevirir.
/// 5.1/7.1: orta kanal ve arka kanallar sol/sağa katılır.
pub fn stereoya(girdi_f32: &[f32], kanal: usize, cikti: &mut Vec<i16>) {
    let kare = girdi_f32.len() / kanal.max(1);
    cikti.reserve(kare * 2);
    let sik = |x: f32| (x.clamp(-1.0, 1.0) * 32767.0) as i16;
    for k in 0..kare {
        let f = &girdi_f32[k * kanal..(k + 1) * kanal];
        let (l, r) = match kanal {
            1 => (f[0], f[0]),
            2 => (f[0], f[1]),
            _ => {
                let c = f.get(2).copied().unwrap_or(0.0) * 0.707;
                let (mut l, mut r) = (f[0] + c, f[1] + c);
                // 4: arka sol/sağ; 6+: 3 = LFE (atlanır), 4/5 arka, 6/7 yan
                let ek: &[(usize, usize)] = if kanal == 4 { &[(2, 3)] } else { &[(4, 5), (6, 7)] };
                for &(a, b) in ek {
                    if kanal == 4 {
                        l += f[a] * 0.5;
                        r += f[b] * 0.5;
                    } else if b < kanal {
                        l += f[a] * 0.5;
                        r += f[b] * 0.5;
                    }
                }
                (l * 0.6, r * 0.6)
            }
        };
        cikti.push(sik(l));
        cikti.push(sik(r));
    }
}

#[cfg(test)]
mod testler {
    use super::*;

    #[test]
    fn yedekli_paketler() {
        let mut p = Paketleyici::yeni(48000);
        let mut paketler: Vec<Vec<u8>> = Vec::new();
        let ses: Vec<i16> = (0..KARE * 2 * 3).map(|i| ((i % 200) as i16 - 100) * 50).collect();
        p.ekle(&ses, 9, &mut |b| paketler.push(b.to_vec()));
        assert_eq!(paketler.len(), 3);
        let b0 = Baslik::oku(&paketler[0]).unwrap();
        let b1 = Baslik::oku(&paketler[1]).unwrap();
        assert_eq!((b0.sira, b0.bayrak, b0.oturum), (0, 0, 9));
        assert_eq!((b1.sira, b1.bayrak, b1.konum), (1, YEDEK_VAR, KARE as u32));
        assert_eq!(paketler[0].len(), BASLIK + KARE * 4);
        assert_eq!(paketler[1].len(), BASLIK + KARE * 8);
        // 1. paketin yedeği 0. paketin yüküdür
        assert_eq!(&paketler[1][BASLIK + KARE * 4..], &paketler[0][BASLIK..]);
    }

    #[test]
    fn sessizlikte_ses_gitmez() {
        let mut p = Paketleyici::yeni(48000);
        let mut turler = Vec::new();
        let sessiz = vec![0i16; KARE * 2 * 40];
        p.ekle(&sessiz, 1, &mut |b| turler.push(Baslik::oku(b).unwrap().tur));
        assert!(turler.iter().all(|t| *t == Tur::Sessizlik));
        assert_eq!(turler.len(), 1, "100 ms'de en fazla bir sessizlik paketi");
        let ses = vec![3000i16; KARE * 2];
        turler.clear();
        p.ekle(&ses, 1, &mut |b| turler.push(Baslik::oku(b).unwrap().tur));
        assert_eq!(turler, vec![Tur::Ses]);
        assert!(p.caliyor());
    }

    #[test]
    fn coklu_kanal() {
        let mut c = Vec::new();
        stereoya(&[0.5, -0.5, 0.0, 0.0, 0.0, 0.0], 6, &mut c);
        assert_eq!(c.len(), 2);
        assert!(c[0] > 0 && c[1] < 0);
    }
}
