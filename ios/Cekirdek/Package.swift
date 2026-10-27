// swift-tools-version:5.9
// Saf Swift çekirdek: paket biçimi, ses tamponu, geçiş kuralı, ekolayzer verisi.
// UIKit/AVFoundation YOK → Linux'ta `swift test` ile doğrulanır.
import PackageDescription

let package = Package(
    name: "Cekirdek",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Cekirdek", targets: ["Cekirdek"])],
    targets: [
        .target(name: "Cekirdek"),
        // Yalnız Linux'ta uçtan uca deneme (Rust PC programıyla); uygulamaya girmez.
        .executableTarget(name: "uctanuca", dependencies: ["Cekirdek"]),
        .testTarget(name: "CekirdekTests", dependencies: ["Cekirdek"]),
    ]
)
