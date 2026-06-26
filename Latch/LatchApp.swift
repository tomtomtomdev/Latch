import SwiftUI
import LatchData

@main
struct LatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(model: TargetPickerModel(
                discovery: LibprocTargetDiscovery(lister: LibprocProcessLister())
            ))
        }
    }
}
