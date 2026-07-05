import SwiftUI

@main
struct VesselApp: App {
    var body: some Scene {
        // Single-window scene: prevents macOS state restoration from spawning
        // duplicate windows (each with its own polling loop) on relaunch.
        Window("Vessel", id: "main") {
            ContentView()
                .containerBackground(.thinMaterial, for: .window)
        }
        .windowResizability(.contentSize)
    }
}
