import Foundation
import Testing

@testable import LauncherKit

private func makeStore() -> (StateStore, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "hmcl-state-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (StateStore(url: root.appending(path: "state.json")), root)
}

@Suite struct LaunchSettingsStateTests {
    @Test func offlineAccountsAreOnByDefault() {
        #expect(LauncherState().offlineAccountsEnabled)
        #expect(LauncherState().customJavaOptions.isEmpty)
    }

    @Test func bothFieldsRoundTrip() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var state = LauncherState()
        state.offlineAccountsEnabled = false
        state.customJavaOptions = "-Xmx4G -Dfoo=\"a b\""
        try store.save(state)

        #expect(store.load() == state)
    }

    /// A state.json written by 1.0.0 has neither key. It must keep the mode and
    /// the selections rather than being thrown away for a fresh default.
    @Test func stateFromTheFirstReleaseStillLoads() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = """
        {
          "mode" : "advanced",
          "selectedLauncherVersion" : "3.16.3",
          "selectedRuntimeID" : "liberica-25.0.4+9"
        }
        """
        try Data(legacy.utf8).write(to: store.url)

        let state = store.load()

        #expect(state.mode == .advanced)
        #expect(state.selectedLauncherVersion == "3.16.3")
        #expect(state.selectedRuntimeID == "liberica-25.0.4+9")
        #expect(state.offlineAccountsEnabled)
        #expect(state.customJavaOptions.isEmpty)
    }
}
