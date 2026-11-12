import SwiftUI

@main
struct SyncYourPodsApp: App {
    @State private var denetci = Denetci()

    var body: some Scene {
        WindowGroup {
            AnaEkran()
                .environment(denetci)
        }
    }
}
