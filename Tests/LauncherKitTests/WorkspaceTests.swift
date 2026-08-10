import Foundation
import Testing

@testable import LauncherKit

private func makeTempRoot() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "hmcl-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct WorkspaceTests {
    @Test func everyPathLivesUnderTheRoot() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(root: root)

        let prefix = root.standardizedFileURL.path
        for path in workspace.allPaths {
            #expect(path.standardizedFileURL.path.hasPrefix(prefix))
        }
    }

    @Test func rootSitsInsideApplicationSupport() throws {
        let workspace = try Workspace.applicationSupport()
        #expect(workspace.root.path.contains("Application Support"))
        #expect(workspace.root.lastPathComponent == AppIdentity.bundleIdentifier)
    }

    @Test func createDirectoriesMakesEveryDirectory() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(root: root)

        try workspace.createDirectories()

        for directory in workspace.allDirectories {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            #expect(exists, "missing \(directory.lastPathComponent)")
            #expect(isDirectory.boolValue)
        }
    }

    @Test func createDirectoriesRunTwiceChangesNothing() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(root: root)

        try workspace.createDirectories()
        try workspace.createDirectories()

        #expect(FileManager.default.fileExists(atPath: workspace.runtimes.path))
    }
}

@Suite struct StateStoreTests {
    @Test func missingFileYieldsDefaults() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(url: root.appending(path: "state.json"))

        let state = store.load()

        #expect(state.mode == .simple)
        #expect(state.selectedLauncherVersion == nil)
        #expect(state.selectedRuntimeID == nil)
    }

    @Test func stateRoundTrips() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(url: root.appending(path: "state.json"))

        var state = LauncherState()
        state.mode = .advanced
        state.selectedLauncherVersion = "3.16.3"
        state.selectedRuntimeID = "liberica-25.0.4+9"
        try store.save(state)

        #expect(store.load() == state)
    }

    @Test func corruptFileYieldsDefaultsInsteadOfThrowing() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "state.json")
        try Data("not json at all".utf8).write(to: url)
        let store = StateStore(url: url)

        #expect(store.load() == LauncherState())
    }

    @Test func savingCreatesMissingParentDirectories() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "nested/deeper/state.json")
        let store = StateStore(url: url)

        try store.save(LauncherState())

        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
