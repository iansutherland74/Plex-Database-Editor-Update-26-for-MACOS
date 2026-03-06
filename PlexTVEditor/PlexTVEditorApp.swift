import SwiftUI

@main
struct PlexTVEditorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    // Open settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
