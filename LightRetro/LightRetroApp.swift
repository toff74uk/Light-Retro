import SwiftUI

@main struct LightRetroApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var controllers = ControllerHub()
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(store).environmentObject(controllers)
                .preferredColorScheme(.dark).tint(store.tint)
                .onChange(of: store.profile.controlResponse, initial: true) { _, value in
                    controllers.response = value ?? .standard
                }
        }
    }
}
