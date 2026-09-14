import SwiftUI

@main
struct MirageApp: App {
    @State private var session = SpoofSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .frame(minWidth: 900, minHeight: 600)
                .task { await session.discoverDevices() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Simulation") {
                Button("Arrêter la simulation") {
                    Task { await session.clearLocation() }
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button("Importer un GPX…") { session.isImporting = true }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
