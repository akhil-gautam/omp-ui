import SwiftUI

@main
struct OMPApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        Window("omp-ui", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 600)
                // The system draws the fields and the popovers, so it has to
                // agree with the theme.
                .preferredColorScheme(store.palette.isLight ? .light : .dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            // The button in the sidebar offers ⌘N, so the menu has to keep it.
            CommandGroup(after: .newItem) {
                Button("New Project") {
                    Task { await store.addProjectPicker() }
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("New Conversation") {
                    Task { await store.newConversation() }
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(store.activeID == nil)
            }
        }
    }
}
