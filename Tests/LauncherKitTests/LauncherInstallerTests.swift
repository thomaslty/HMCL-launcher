import Foundation
import Testing

@testable import LauncherKit

/// Writes a stand-in jar so the download path can be exercised offline.
private struct StubJarDownloader: FileDownloading {
    var failMidway = false

    func download(
        from url: URL,
        to destination: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        onProgress(0.5)
        if failMidway {
            throw RuntimeInstallError.unexpectedStatus(500)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("PK\u{03}\u{04}fake jar".utf8).write(to: destination)
        onProgress(1)
    }
}

private func makeWorkspace() -> Workspace {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "hmcl-ws-\(UUID().uuidString)")
    let workspace = Workspace(root: root)
    try? workspace.createDirectories()
    return workspace
}

private func release(_ version: String) -> HMCLRelease {
    HMCLRelease(
        version: version,
        jarName: "HMCL-\(version).jar",
        jarURL: URL(string: "https://example.invalid/HMCL-\(version).jar")!,
        jarSize: 10_319_057
    )
}

@Suite struct LauncherInstallerTests {
    @Test func installsTheJarIntoTheLaunchersDirectory() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let installer = LauncherInstaller(workspace: workspace, downloader: StubJarDownloader())

        let launcher = try await installer.install(release("3.16.3")) { _ in }

        #expect(launcher.version == "3.16.3")
        #expect(launcher.jarURL.lastPathComponent == "HMCL-3.16.3.jar")
        #expect(FileManager.default.fileExists(atPath: launcher.jarURL.path))
    }

    @Test func reportsProgressWhileDownloading() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let installer = LauncherInstaller(workspace: workspace, downloader: StubJarDownloader())

        let recorder = ProgressRecorder()
        _ = try await installer.install(release("3.16.3")) { recorder.record($0) }

        let seen = recorder.values
        #expect(!seen.isEmpty)
        #expect(seen.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func interruptedDownloadLeavesNothingBehind() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let installer = LauncherInstaller(
            workspace: workspace,
            downloader: StubJarDownloader(failMidway: true)
        )

        await #expect(throws: (any Error).self) {
            try await installer.install(release("3.16.3")) { _ in }
        }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: workspace.launchers.path)
        #expect(leftovers.isEmpty)
    }

    @Test func listingParsesVersionsNewestFirst() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let installer = LauncherInstaller(workspace: workspace, downloader: StubJarDownloader())

        _ = try await installer.install(release("3.16.2")) { _ in }
        _ = try await installer.install(release("3.16.3")) { _ in }

        #expect(installer.installed().map(\.version) == ["3.16.3", "3.16.2"])
    }

    @Test func ignoresFilesThatAreNotHMCLJars() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try Data("junk".utf8).write(to: workspace.launchers.appending(path: "notes.txt"))
        try Data("junk".utf8).write(to: workspace.launchers.appending(path: "other.jar"))
        let installer = LauncherInstaller(workspace: workspace, downloader: StubJarDownloader())

        #expect(installer.installed().isEmpty)
    }

    @Test func reinstallingReplacesInsteadOfDuplicating() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let installer = LauncherInstaller(workspace: workspace, downloader: StubJarDownloader())

        _ = try await installer.install(release("3.16.3")) { _ in }
        _ = try await installer.install(release("3.16.3")) { _ in }

        #expect(installer.installed().count == 1)
    }

    @Test func removingDropsTheJar() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let installer = LauncherInstaller(workspace: workspace, downloader: StubJarDownloader())
        let launcher = try await installer.install(release("3.16.3")) { _ in }

        try installer.remove(launcher)

        #expect(installer.installed().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: launcher.jarURL.path))
    }
}

/// Progress callbacks arrive on whatever thread the downloader is on.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func record(_ value: Double) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
