import SwiftUI

@main struct LightRetroApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var controllers = ControllerHub()
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(store).environmentObject(controllers)
                .preferredColorScheme(.dark).tint(store.tint)
        }
    }
}
