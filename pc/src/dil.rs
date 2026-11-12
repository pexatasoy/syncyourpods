//! Arayüz dili: Windows'un görüntü dili Türkçeyse Türkçe, değilse İngilizce.
//! `SYP_DIL=tr|en` ortam değişkeni bu seçimi ezer (deneme için).

use std::sync::OnceLock;

pub fn turkce() -> bool {
    static T: OnceLock<bool> = OnceLock::new();
    *T.get_or_init(|| {
        if let Ok(d) = std::env::var("SYP_DIL") {
            return d.starts_with("tr");
        }
        #[cfg(windows)]
        {
            // LANG_TURKISH = 0x1F (birincil dil kimliği: alt 10 bit)
            let id = unsafe { windows::Win32::Globalization::GetUserDefaultUILanguage() };
            id & 0x3ff == 0x1f
        }
        #[cfg(not(windows))]
        {
            std::env::var("LANG").map(|l| l.starts_with("tr")).unwrap_or(false)
        }
    })
}

/// İki dilli metin: `t("Çıkış", "Quit")`.
pub fn t(tr: &'static str, en: &'static str) -> &'static str {
    if turkce() { tr } else { en }
}

pub fn kod() -> &'static str {
    t("tr", "en")
}
