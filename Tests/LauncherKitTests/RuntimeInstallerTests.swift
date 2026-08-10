import Foundation
import Testing

@testable import LauncherKit

// MARK: - Fixtures

/// Builds a real .tar.gz on disk whose inner layout we control, so extraction
/// and Java-home resolution are exercised against actual archives.
private func makeArchive(layout: [String]) throws -> (url: URL, sha1: String) {
    let staging = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "hmcl-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

    for relative in layout {
        let file = staging.appending(path: relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\necho fixture\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    let archive = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "hmcl-fixture-\(UUID().uuidString).tar.gz")
    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tar.arguments = ["-czf", archive.path, "-C", staging.path] + uniqueTopLevels(of: layout)
    try tar.run()
    tar.waitUntilExit()
    try FileManager.default.removeItem(at: staging)

    return (archive, try Checksum.sha1(ofFileAt: archive))
}

private func uniqueTopLevels(of layout: [String]) -> [String] {
    var seen: [String] = []
    for path in layout {
        let top = String(path.split(separator: "/")[0])
        if !seen.contains(top) { seen.append(top) }
    }
    return seen
}

/// Stands in for the network by copying a fixture archive into place.
struct StubDownloader: FileDownloading {
    let source: URL

    func download(
        from url: URL,
        to destination: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        onProgress(0)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
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

private let libericaAPIJSON = Data("""
[{"bitness":64,"latestLTS":true,"updateVersion":4,
  "downloadUrl":"https://github.com/bell-sw/Liberica/releases/download/25.0.4+9/bellsoft-jre25.0.4+9-macos-aarch64-full.tar.gz",
  "LTS":true,"bundleType":"jre-full","featureVersion":25,"packageType":"tar.gz","FX":true,"GA":true,
  "architecture":"arm","os":"macos","version":"25.0.4+9",
  "sha1":"e0b7a1ce9205560eef4a5afb1706c3fbea0a037b",
  "filename":"bellsoft-jre25.0.4+9-macos-aarch64-full.tar.gz","size":126032886}]
""".utf8)

// MARK: - Tests

@Suite struct LibericaClientTests {
    @Test func resolvesTheLatestLTSFullJRE() async throws {
        let fetcher = StubFetcher([HTTPResponse(status: 200, body: libericaAPIJSON, headers: [:])])
        let client = LibericaClient(fetcher: fetcher)

        let build = try await client.latestLTSFullJRE()

        #expect(build.version == "25.0.4+9")
        #expect(build.sha1 == "e0b7a1ce9205560eef4a5afb1706c3fbea0a037b")
        #expect(build.runtimeID == "liberica-25.0.4+9")
    }

    @Test func asksForAnAarch64FullJRE() async throws {
        let fetcher = StubFetcher([HTTPResponse(status: 200, body: libericaAPIJSON, headers: [:])])
        _ = try await LibericaClient(fetcher: fetcher).latestLTSFullJRE()

        let query = await fetcher.requestedURLs[0].query ?? ""
        #expect(query.contains("bundle-type=jre-full"))
        #expect(query.contains("os=macos"))
        #expect(query.contains("arch=arm"))
        #expect(query.contains("release-type=lts"))
    }

    @Test func emptyResultFails() async throws {
        let fetcher = StubFetcher([HTTPResponse(status: 200, body: Data("[]".utf8), headers: [:])])
        let client = LibericaClient(fetcher: fetcher)

        await #expect(throws: RuntimeInstallError.noBuildAvailable) {
            try await client.latestLTSFullJRE()
        }
    }
}

@Suite struct RuntimeInstallerTests {
    @Test func installsAnArchiveThatNestsTheRuntimeInItsOwnDirectory() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let (archive, sha1) = try makeArchive(layout: ["jre-25.0.4-full.jre/bin/java"])
        defer { try? FileManager.default.removeItem(at: archive) }

        let installer = RuntimeInstaller(workspace: workspace, downloader: StubDownloader(source: archive))
        let build = JavaBuild(
            version: "25.0.4+9",
            downloadURL: URL(string: "https://example.invalid/jre.tar.gz")!,
            sha1: sha1
        )

        let runtime = try await installer.install(build) { _ in }

        #expect(runtime.id == "liberica-25.0.4+9")
        #expect(FileManager.default.isExecutableFile(atPath: runtime.javaExecutable.path))
        // /var is a symlink to /private/var, so compare resolved paths.
        let installedUnder = runtime.home.resolvingSymlinksInPath().path
        let runtimesRoot = workspace.runtimes.resolvingSymlinksInPath().path
        #expect(installedUnder.hasPrefix(runtimesRoot))
    }

    @Test func installsAnArchiveUsingTheMacOSBundleLayout() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let (archive, sha1) = try makeArchive(layout: ["jre.jdk/Contents/Home/bin/java"])
        defer { try? FileManager.default.removeItem(at: archive) }

        let installer = RuntimeInstaller(workspace: workspace, downloader: StubDownloader(source: archive))
        let build = JavaBuild(
            version: "21.0.5+11",
            downloadURL: URL(string: "https://example.invalid/jre.tar.gz")!,
            sha1: sha1
        )

        let runtime = try await installer.install(build) { _ in }

        #expect(runtime.home.lastPathComponent == "Home")
        #expect(FileManager.default.isExecutableFile(atPath: runtime.javaExecutable.path))
    }

    @Test func checksumMismatchAbortsAndLeavesNothingBehind() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let (archive, _) = try makeArchive(layout: ["jre-25.0.4-full.jre/bin/java"])
        defer { try? FileManager.default.removeItem(at: archive) }

        let installer = RuntimeInstaller(workspace: workspace, downloader: StubDownloader(source: archive))
        let build = JavaBuild(
            version: "25.0.4+9",
            downloadURL: URL(string: "https://example.invalid/jre.tar.gz")!,
            sha1: "0000000000000000000000000000000000000000"
        )

        await #expect(throws: RuntimeInstallError.checksumMismatch) {
            try await installer.install(build) { _ in }
        }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: workspace.runtimes.path)
        #expect(leftovers.isEmpty)
    }

    @Test func listingSortsNewestFirst() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let (archive, sha1) = try makeArchive(layout: ["jre/bin/java"])
        defer { try? FileManager.default.removeItem(at: archive) }
        let installer = RuntimeInstaller(workspace: workspace, downloader: StubDownloader(source: archive))
        let url = URL(string: "https://example.invalid/jre.tar.gz")!

        _ = try await installer.install(JavaBuild(version: "21.0.5+11", downloadURL: url, sha1: sha1)) { _ in }
        _ = try await installer.install(JavaBuild(version: "25.0.4+9", downloadURL: url, sha1: sha1)) { _ in }

        let installed = installer.installed()

        #expect(installed.map(\.version) == ["25.0.4+9", "21.0.5+11"])
    }

    @Test func reinstallingReplacesInsteadOfDuplicating() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let (archive, sha1) = try makeArchive(layout: ["jre/bin/java"])
        defer { try? FileManager.default.removeItem(at: archive) }
        let installer = RuntimeInstaller(workspace: workspace, downloader: StubDownloader(source: archive))
        let build = JavaBuild(
            version: "25.0.4+9",
            downloadURL: URL(string: "https://example.invalid/jre.tar.gz")!,
            sha1: sha1
        )

        _ = try await installer.install(build) { _ in }
        _ = try await installer.install(build) { _ in }

        #expect(installer.installed().count == 1)
    }

    @Test func removingDropsTheRuntime() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let (archive, sha1) = try makeArchive(layout: ["jre/bin/java"])
        defer { try? FileManager.default.removeItem(at: archive) }
        let installer = RuntimeInstaller(workspace: workspace, downloader: StubDownloader(source: archive))
        let runtime = try await installer.install(
            JavaBuild(version: "25.0.4+9", downloadURL: URL(string: "https://example.invalid/j.tar.gz")!, sha1: sha1)
        ) { _ in }

        try installer.remove(runtime)

        #expect(installer.installed().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: runtime.home.path))
    }
}
