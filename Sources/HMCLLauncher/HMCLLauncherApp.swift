import LauncherKit
import SwiftUI

@main
struct HMCLLauncherApp: App {
    var body: some Scene {
        WindowGroup(AppIdentity.displayName) {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    var body: some View {
        Text(AppIdentity.displayName)
            .padding(40)
    }
}
