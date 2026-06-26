import SwiftUI
import LatchDomain

struct ContentView: View {
    // Slice 0 smoke: the App layer links the package and reads a Domain type.
    // Replaced by the real target-picker UI in slice 1.
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Latch")
                .font(.title)
            Text("Tracking \(SignalKind.allCases.count) health signals")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 200)
    }
}

#Preview {
    ContentView()
}
