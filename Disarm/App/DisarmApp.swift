import SwiftUI

@main
struct DisarmApp: App {
    @State private var engine = GameEngine()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                .preferredColorScheme(.dark)
        }
        .onChange(of: phase) { _, new in
            if new == .background || new == .inactive {
                engine.save()
                engine.audio.pauseMusic()
            } else if new == .active {
                engine.audio.startMusic()
            }
        }
    }
}
