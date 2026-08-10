import Foundation
import Testing

@testable import LauncherKit

/// Drives the real flow: GitHub, BellSoft, a 126 MB download, extraction, and an
/// actual HMCL process — into the real workspace, exactly as pressing Start
/// does.
///
/// Off by default because it touches the network and the user's Application
/// Support directory. Run it with:
///
///     HMCL_INTEGRATION=1 swift test --filter EndToEnd
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HMCL_INTEGRATION"] == "1"))
struct EndToEndTests {
    @Test func coldStartInstallsEverythingAndLaunchesHMCL() async throws {
        let workspace = try Workspace.applicationSupport()
        try workspace.createDirectories()

        let fetcher = URLSessionFetcher()
        let downloader = URLSessionDownloader()

        // 1. What is the latest HMCL?
        let lookup = try await GitHubReleaseClient(
            fetcher: fetcher,
            cacheURL: workspace.releaseCacheFile
        ).latestRelease()
        print("latest HMCL: \(lookup.release.version) via \(lookup.source)")
        #expect(!lookup.release.version.isEmpty)

        // 2. Download the jar.
        let launcher = try await LauncherInstaller(workspace: workspace, downloader: downloader)
            .install(lookup.release) { _ in }
        #expect(FileManager.default.fileExists(atPath: launcher.jarURL.path))
        print("installed \(launcher.jarURL.lastPathComponent)")

        // 3. Resolve and install the latest LTS Liberica Full JRE.
        let build = try await LibericaClient(fetcher: fetcher).latestLTSFullJRE()
        print("liberica build: \(build.version)")
        let runtime = try await RuntimeInstaller(workspace: workspace, downloader: downloader)
            .install(build) { _ in }
        #expect(FileManager.default.isExecutableFile(atPath: runtime.javaExecutable.path))
        print("installed runtime at \(runtime.home.path)")

        // 4. Launch HMCL for real.
        let service = HMCLLaunchService(workspace: workspace)
        let running = try service.launch(runtime: runtime, launcher: launcher)
        #expect(running.processIdentifier > 0)
        print("hmcl pid \(running.processIdentifier), log \(running.logFile.path)")

        // 5. HMCL must reach its JavaFX banner, which only appears once the UI
        //    toolkit is up. That is the proof the Full JRE did its job.
        let log = try await waitForLine(containing: "JavaFX Version", in: running.logFile)
        print(log.split(separator: "\n").prefix(24).joined(separator: "\n"))
        #expect(log.contains("JavaFX Version"))
        #expect(log.contains(workspace.hmclUserHome.path), "HMCL should be using the scoped user home")

        // 6. And it should still be alive when we look.
        #expect(kill(running.processIdentifier, 0) == 0, "HMCL process should be running")

        // Leave the machine as we found it.
        kill(running.processIdentifier, SIGTERM)
    }

    private func waitForLine(
        containing needle: String,
        in url: URL,
        timeout: TimeInterval = 90
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url) {
                let text = String(decoding: data, as: UTF8.self)
                if text.contains(needle) { return text }
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
