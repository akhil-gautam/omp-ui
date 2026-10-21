import SwiftUI

@main
struct OMPApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        Window("omp-ui", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
    }
}
