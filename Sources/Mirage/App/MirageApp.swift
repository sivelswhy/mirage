import SwiftUI

@main
struct MirageApp: App {
    @State private var session = SpoofSession()
    @State private var updater = Updater()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(updater)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    session.startMonitoring()
                    await updater.checkAtLaunch()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Rechercher des mises à jour…") {
                    Task {
                        updater.phase = .idle
                        await updater.checkAtLaunch()
                    }
                }
            }
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
