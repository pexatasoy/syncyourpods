//! Tepsiden açılan panel (Windows 11 hızlı ayarları gibi, sağ altta). Arayüz panel.html — Apple dilinde,
//! iPhone uygulamasının ekranlarının aynısı. Ayarlar iki yönlü eşit: panelde değişen iPhone'a gider,
//! iPhone'da değişen panele yansır (telefon "phone" durum mesajı, bkz. sunucu.rs).
//!
//! Kaynak: panel kapalıyken WebView yok. Kapandıktan 2 dakika sonra tamamen silinir (bellek geri verilir).

use crate::ortak::{MedyaIstek, Ortak};
use crate::protokol::Mesaj;
use crate::tepsi;
use serde_json::{json, Value};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tao::dpi::{LogicalSize, PhysicalPosition};
use tao::event::{Event, StartCause, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoopBuilder, EventLoopProxy, EventLoopWindowTarget};
use tao::platform::windows::{WindowBuilderExtWindows, WindowExtWindows};
use tao::window::{Window, WindowBuilder};
use tray_icon::menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use tray_icon::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent};
use windows::core::w;
use windows::Win32::Foundation::{HWND, RECT};
use windows::Win32::Graphics::Dwm::{DwmSetWindowAttribute, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND, DWM_WINDOW_CORNER_PREFERENCE};
use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_DWORD};
use windows::Win32::UI::WindowsAndMessaging::{SystemParametersInfoW, SPI_GETWORKAREA, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS};
use wry::{WebContext, WebView, WebViewBuilder};

const HTML: &str = include_str!("panel.html");
const GENISLIK: f64 = 380.0;
const YUKSEKLIK: f64 = 700.0;
pub const SITE: &str = "https://chainmedia.co/fotoyol/syncyourpods-14c6606f54315e91/";

enum Olay {
    Ipc(String),
}

struct Panel {
    pencere: Window,
    web: WebView,
}

pub fn calistir(o: Arc<Ortak>) {
    let dongu = EventLoopBuilder::<Olay>::with_user_event().build();
    let vekil = dongu.create_proxy();

    let menu = Menu::new();
    let ac = MenuItem::new(crate::dil::t("SyncYourPods’u aç", "Open SyncYourPods"), true, None);
    let cikis = MenuItem::new(crate::dil::t("Çıkış", "Quit"), true, None);
    let _ = menu.append_items(&[&ac, &PredefinedMenuItem::separator(), &cikis]);
    let tepsi_simgesi: Option<TrayIcon> = TrayIconBuilder::new()
        .with_menu(Box::new(menu))
        .with_menu_on_left_click(false)
        .with_tooltip(crate::dil::t("SyncYourPods — iPhone bekleniyor", "SyncYourPods — waiting for iPhone"))
        .with_icon(tepsi::simge(false, false))
        .build()
        .map_err(|e| crate::gunluk!("tepsi simgesi kurulamadı: {}", e))
        .ok();

    let mut baglam = WebContext::new(Some(crate::ayarlar::klasor().join("webview")));
    let mut panel: Option<Panel> = None;
    let mut gorunur = false;
    let mut gizlenme: Option<Instant> = None;
    let mut son_itme = Instant::now();
    let mut onceki_simge: (Option<String>, bool, bool) = (None, true, false);

    dongu.run(move |olay, hedef, akis| {
        *akis = ControlFlow::WaitUntil(Instant::now() + Duration::from_millis(if gorunur { 80 } else { 400 }));

        match olay {
            Event::NewEvents(StartCause::Init) => {
                // --sorma: açılış sorusunu atla (otomatik deneme). --panel: paneli hemen aç.
                let arg: Vec<String> = std::env::args().collect();
                if !arg.iter().any(|a| a == "--sorma") {
                    acilis_sor();
                }
                if arg.iter().any(|a| a == "--panel") {
                    goster(&o, hedef, &vekil, &mut baglam, &mut panel, &mut gorunur);
                }
            }
            Event::UserEvent(Olay::Ipc(s)) => {
                let Ok(v) = serde_json::from_str::<Value>(&s) else { return };
                match v["k"].as_str().unwrap_or("") {
                    "hazir" => son_itme = Instant::now() - Duration::from_secs(1),
                    "gizle" => gizle(&o, &mut panel, &mut gorunur, &mut gizlenme),
                    "cikis" => {
                        cik(&o);
                        *akis = ControlFlow::Exit;
                        return;
                    }
                    _ => ipc(&o, &v),
                }
            }
            Event::WindowEvent { event: WindowEvent::Focused(false), .. } => {
                if gorunur {
                    gizle(&o, &mut panel, &mut gorunur, &mut gizlenme);
                }
            }
            _ => {}
        }

        while let Ok(e) = TrayIconEvent::receiver().try_recv() {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                // Panel açıkken simgeye tıklamak önce odağı kaybettirip paneli kapatır; aynı tıklama yeniden açmasın.
                let az_once = gizlenme.map(|t| t.elapsed() < Duration::from_millis(350)).unwrap_or(false);
                if gorunur {
                    gizle(&o, &mut panel, &mut gorunur, &mut gizlenme);
                } else if !az_once {
                    goster(&o, hedef, &vekil, &mut baglam, &mut panel, &mut gorunur);
                    son_itme = Instant::now() - Duration::from_secs(1);
                }
            }
        }
        while let Ok(e) = MenuEvent::receiver().try_recv() {
            if e.id == ac.id() {
                goster(&o, hedef, &vekil, &mut baglam, &mut panel, &mut gorunur);
                son_itme = Instant::now() - Duration::from_secs(1);
            } else if e.id == cikis.id() {
                cik(&o);
                *akis = ControlFlow::Exit;
                return;
            }
        }

        if gorunur && son_itme.elapsed() >= Duration::from_millis(150) {
            son_itme = Instant::now();
            if let Some(p) = &panel {
                let _ = p.web.evaluate_script(&format!("window.durum&&window.durum({})", durum_json(&o)));
            }
        }

        // Kapalı panel 2 dakika sonra bellekten silinir.
        if !gorunur && panel.is_some() && gizlenme.map(|t| t.elapsed() > Duration::from_secs(120)).unwrap_or(false) {
            panel = None;
        }

        // Tepsi simgesi: bekliyor (gri) / bağlı (mavi) / iPhone öncelikte (turuncu).
        let d = o.durum.lock().unwrap();
        let simdi = (d.telefon.clone(), o.kulaklik.load(Ordering::Relaxed), d.odak_telefonda);
        let (caliyor, mik) = (d.caliyor, d.mik == "on");
        drop(d);
        if simdi != onceki_simge {
            if let Some(t) = &tepsi_simgesi {
                let _ = t.set_icon(Some(tepsi::simge(simdi.0.is_some(), simdi.2)));
                let ipucu = match &simdi.0 {
                    None => crate::dil::t("SyncYourPods — iPhone bekleniyor", "SyncYourPods — waiting for iPhone").to_string(),
                    Some(ad) if !simdi.1 => format!("SyncYourPods — {} · {}", ad, crate::dil::t("AirPods kutuda", "AirPods in case")),
                    Some(ad) if simdi.2 => format!("SyncYourPods — {} · {}", ad, crate::dil::t("iPhone sesi öncelikte", "iPhone audio has priority")),
                    Some(ad) => format!("SyncYourPods — {} · {}{}", ad, if caliyor { crate::dil::t("PC sesi AirPods’ta", "PC audio on AirPods") } else { crate::dil::t("PC sessiz", "PC quiet") }, if mik { crate::dil::t(" · mikrofon açık", " · mic on") } else { "" }),
                };
                let _ = t.set_tooltip(Some(ipucu));
            }
            onceki_simge = simdi;
        }
    });
}

fn goster(o: &Arc<Ortak>, hedef: &EventLoopWindowTarget<Olay>, vekil: &EventLoopProxy<Olay>, baglam: &mut WebContext, panel: &mut Option<Panel>, gorunur: &mut bool) {
    if panel.is_none() {
        *panel = olustur(hedef, vekil, baglam);
    }
    let Some(p) = panel.as_ref() else { return };
    konumla(&p.pencere);
    let _ = p.web.evaluate_script(&format!("window.durum&&window.durum({});window.acildi&&window.acildi()", durum_json(o)));
    p.pencere.set_visible(true);
    p.pencere.set_focus();
    *gorunur = true;
    o.gonder(&Mesaj::Watch { on: true });
}

fn gizle(o: &Arc<Ortak>, panel: &mut Option<Panel>, gorunur: &mut bool, gizlenme: &mut Option<Instant>) {
    if let Some(p) = panel.as_ref() {
        p.pencere.set_visible(false);
    }
    *gorunur = false;
    *gizlenme = Some(Instant::now());
    o.gonder(&Mesaj::Watch { on: false });
}

fn olustur(hedef: &EventLoopWindowTarget<Olay>, vekil: &EventLoopProxy<Olay>, baglam: &mut WebContext) -> Option<Panel> {
    let koyu = koyu_tema();
    let pencere = WindowBuilder::new()
        .with_title("SyncYourPods")
        .with_decorations(false)
        .with_resizable(false)
        .with_always_on_top(true)
        .with_skip_taskbar(true)
        .with_undecorated_shadow(true)
        .with_inner_size(LogicalSize::new(GENISLIK, YUKSEKLIK))
        .with_visible(false)
        .build(hedef)
        .map_err(|e| crate::gunluk!("panel penceresi açılamadı: {}", e))
        .ok()?;
    // Windows 11: yuvarlak köşe (Windows 10'da etkisiz, zararsız).
    unsafe {
        let tercih: DWM_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND;
        let _ = DwmSetWindowAttribute(
            HWND(pencere.hwnd() as *mut _),
            DWMWA_WINDOW_CORNER_PREFERENCE,
            &tercih as *const _ as *const _,
            std::mem::size_of::<DWM_WINDOW_CORNER_PREFERENCE>() as u32,
        );
    }
    let v = vekil.clone();
    let web = WebViewBuilder::new_with_web_context(baglam)
        .with_html(HTML.replacen("__DIL__", crate::dil::kod(), 1))
        .with_background_color(if koyu { (0, 0, 0, 255) } else { (242, 242, 247, 255) })
        .with_devtools(false)
        .with_ipc_handler(move |istek| {
            let _ = v.send_event(Olay::Ipc(istek.body().clone()));
        })
        .build(&pencere);
    match web {
        Ok(web) => Some(Panel { pencere, web }),
        Err(e) => {
            crate::gunluk!("WebView2 açılamadı: {}", e);
            tepsi::uyari(crate::dil::t("Panel için Microsoft WebView2 gerekiyor (Windows 11'de hazır gelir).\n\nAçılacak sayfadan “Evergreen Bootstrapper”ı kurup SyncYourPods'u yeniden açabilirsin. Ses aktarımı bu arada çalışmaya devam eder.", "The panel needs Microsoft WebView2 (it comes with Windows 11).\n\nInstall the “Evergreen Bootstrapper” from the page that opens, then start SyncYourPods again. Audio keeps streaming in the meantime."));
            let _ = std::process::Command::new("explorer.exe").arg("https://developer.microsoft.com/microsoft-edge/webview2/").spawn();
            None
        }
    }
}

/// Sağ alta, görev çubuğunun üstüne (görev çubuğu başka kenardaysa çalışma alanının köşesine).
fn konumla(p: &Window) {
    let mut alan = RECT::default();
    unsafe {
        let _ = SystemParametersInfoW(SPI_GETWORKAREA, 0, Some(&mut alan as *mut _ as *mut _), SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0));
    }
    let boyut = p.outer_size();
    let bosluk = (12.0 * p.scale_factor()) as i32;
    p.set_outer_position(PhysicalPosition::new(alan.right - boyut.width as i32 - bosluk, alan.bottom - boyut.height as i32 - bosluk));
}

fn koyu_tema() -> bool {
    let mut deger: u32 = 1;
    let mut boyut = std::mem::size_of::<u32>() as u32;
    unsafe {
        let _ = RegGetValueW(
            HKEY_CURRENT_USER,
            w!("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
            w!("AppsUseLightTheme"),
            RRF_RT_REG_DWORD,
            None,
            Some(&mut deger as *mut _ as *mut _),
            Some(&mut boyut),
        );
    }
    deger == 0
}

fn durum_json(o: &Arc<Ortak>) -> String {
    let d = o.durum.lock().unwrap().clone();
    let (sus, dur) = {
        let a = o.ayarlar.lock().unwrap();
        (a.pc_sesini_kapat, a.medya_duraklat)
    };
    let tel = o.telefon.lock().unwrap().clone();
    json!({
        "pc": {
            "ad": crate::ayarlar::pc_adi(),
            "cihaz": d.cihaz,
            "caliyor": d.caliyor,
            "baslik": d.baslik,
            "sanatci": d.sanatci,
            "uygulama": d.uygulama,
            "mik": d.mik,
            "pcSesiniKapat": sus,
            "medyaDuraklat": dur,
            "acilis": tepsi::acilista_mi(),
            "surum": env!("CARGO_PKG_VERSION"),
            "site": SITE,
        },
        "telefonAdi": d.telefon,
        "kulaklik": o.kulaklik.load(Ordering::Relaxed),
        "tel": tel,
    })
    .to_string()
}

fn ipc(o: &Arc<Ortak>, v: &Value) {
    match v["k"].as_str().unwrap_or("") {
        // Telefon ayarı: iPhone'a gönder, panel geri sıçramasın diye son durumu da hemen güncelle.
        "set" => {
            if let Some(a) = v.get("v").and_then(|x| x.as_object()) {
                o.gonder(&Mesaj::Set { settings: Value::Object(a.clone()) });
                if let Some(t) = o.telefon.lock().unwrap().as_mut() {
                    if let Some(s) = t.get_mut("settings").and_then(|s| s.as_object_mut()) {
                        for (k, x) in a {
                            s.insert(k.clone(), x.clone());
                        }
                    }
                }
            }
        }
        // PC'ye ait ayarlar
        "pc" => {
            let b = v["v"].as_bool().unwrap_or(false);
            match v["ad"].as_str().unwrap_or("") {
                "pcSesiniKapat" => {
                    o.ayarlar.lock().unwrap().pc_sesini_kapat = b;
                }
                "medyaDuraklat" => {
                    o.ayarlar.lock().unwrap().medya_duraklat = b;
                }
                "acilis" => tepsi::acilis_ayarla(b),
                _ => {}
            }
            o.ayarlar.lock().unwrap().kaydet();
            o.durum_gonder();
        }
        "unut" => {
            let mut a = o.ayarlar.lock().unwrap();
            a.guvenilen.clear();
            a.kaydet();
        }
        "gunluk" => {
            let _ = std::process::Command::new("notepad.exe").arg(crate::ayarlar::klasor().join("gunluk.txt")).spawn();
        }
        "ac" => {
            // Yalnız https bağlantıları (VB-CABLE, indirme sayfası).
            if let Some(u) = v["url"].as_str().filter(|u| u.starts_with("https://")) {
                let _ = std::process::Command::new("explorer.exe").arg(u).spawn();
            }
        }
        _ => {}
    }
}

fn cik(o: &Arc<Ortak>) {
    o.medya_iste(MedyaIstek::Odak(false));
    o.medya_iste(MedyaIstek::Kapat);
    o.gonder(&Mesaj::Bye);
    o.aktif.store(false, Ordering::SeqCst);
    // Yakalama döngüsü durup PC sesini eski hâline getirsin.
    std::thread::sleep(Duration::from_millis(400));
}

/// İlk açılışta: Windows açılınca başlasın mı? (Sormadan eklemek kaba, virüs taramalarını da kuşkulandırıyor.)
fn acilis_sor() {
    let iz = crate::ayarlar::klasor().join(".acilis-soruldu");
    if iz.exists() {
        return;
    }
    let _ = std::fs::write(&iz, b"1");
    use windows::Win32::UI::WindowsAndMessaging::*;
    let evet = unsafe {
        MessageBoxW(None, w!("SyncYourPods çalışıyor; simgesi saatin yanında. Tıklayınca panel açılır.\n\nWindows açılınca kendiliğinden başlasın mı?"), w!("SyncYourPods"), MB_YESNO | MB_ICONQUESTION | MB_SETFOREGROUND) == IDYES
    };
    if evet {
        tepsi::acilis_ayarla(true);
    }
}
