import LauncherKit
import SwiftUI

@main
struct HMCLLauncherApp: App {
    @State private var model: LauncherViewModel

    init() {
        if let directory = ScreenshotRenderer.requestedDirectory() {
            ScreenshotRenderer.renderAll(into: directory)
            exit(0)
        }

        let workspace = (try? Workspace.applicationSupport())
            ?? Workspace(root: URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Library/Application Support/\(AppIdentity.bundleIdentifier)"))
        _model = State(initialValue: LauncherViewModel(workspace: workspace))
    }

    var body: some Scene {
        WindowGroup(AppIdentity.displayName) {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
