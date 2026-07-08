import SwiftUI
import AppKit

@main
struct LatchApp: App {
    /// The one fleet model both surfaces share: the main window streams the selected target while
    /// the menu-bar companion glances at all of them. Owned here so a single instance backs both
    /// scenes. (PLAN slices 11–13)
    @State private var model = MainWindowModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView(model: model)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Latch", systemImage: "link") {
            MenuBarView(model: model, onOpenLatch: openLatch)
        }
        .menuBarExtraStyle(.window)
    }

    /// Bring the main window forward (the companion's `Open Latch`). Activating the app dismisses
    /// the menu-bar popover as a side effect of it losing key.
    private func openLatch() {
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
    }
}
