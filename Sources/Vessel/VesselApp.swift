import SwiftUI

@main
struct VesselApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .containerBackground(.thinMaterial, for: .window)
        }
        .windowResizability(.contentSize)
    }
}
