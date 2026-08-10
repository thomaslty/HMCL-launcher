import Foundation

/// An `HMCL-<version>.jar` sitting in the workspace.
public struct InstalledLauncher: Sendable, Equatable, Identifiable, Hashable {
    public let version: String
    public let jarURL: URL

    public init(version: String, jarURL: URL) {
        self.version = version
        self.jarURL = jarURL
    }

    public var id: String { version }
    public var displayName: String { "HMCL \(version)" }
}

/// Downloads and manages HMCL jars.
///
/// GitHub publishes no checksum for these, so the integrity guarantee here is
/// TLS to github.com and nothing more.
public struct LauncherInstaller: Sendable {
    private let workspace: Workspace
    private let downloader: any FileDownloading

    public init(workspace: Workspace, downloader: any FileDownloading) {
        self.workspace = workspace
        self.downloader = downloader
    }

    public func install(
        _ release: HMCLRelease,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> InstalledLauncher {
        // Download to scratch and move on success, so a failure part way
        // through cannot leave a truncated jar that looks installed.
        let scratch = workspace.root.appending(path: "tmp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let staged = scratch.appending(path: release.jarName)
        try await downloader.download(from: release.jarURL, to: staged, onProgress: onProgress)

        try FileManager.default.createDirectory(at: workspace.launchers, withIntermediateDirectories: true)
        let destination = workspace.launchers.appending(path: release.jarName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: staged, to: destination)

        return InstalledLauncher(version: release.version, jarURL: destination)
    }

    public func installed() -> [InstalledLauncher] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: workspace.launchers,
            includingPropertiesForKeys: nil
        )) ?? []

        return contents
            .compactMap { url -> InstalledLauncher? in
                guard let version = Self.version(fromJarNamed: url.lastPathComponent) else { return nil }
                return InstalledLauncher(version: version, jarURL: url)
            }
            .sorted { VersionOrder.newestFirst($0.version, $1.version) }
    }

    public func remove(_ launcher: InstalledLauncher) throws {
        try FileManager.default.removeItem(at: launcher.jarURL)
    }

    /// "HMCL-3.16.3.jar" -> "3.16.3". Anything else in the directory is ignored.
    static func version(fromJarNamed name: String) -> String? {
        guard name.hasPrefix("HMCL-"), name.hasSuffix(".jar") else { return nil }
        let version = name.dropFirst("HMCL-".count).dropLast(".jar".count)
        guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return String(version)
    }
}
