// Windows: .exe simgesi ve dosya bilgisi (Gezgin'de "SyncYourPods" görünsün).
fn main() {
    println!("cargo:rerun-if-changed=simge.ico");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let mut r = winresource::WindowsResource::new();
        r.set_icon("simge.ico");
        r.set("FileDescription", "SyncYourPods");
        r.set("ProductName", "SyncYourPods");
        r.set("CompanyName", "Efe Atasoy");
        r.set("LegalCopyright", "© 2026 Efe Atasoy");
        r.compile().expect("Windows kaynak dosyası derlenemedi");
    }
}
