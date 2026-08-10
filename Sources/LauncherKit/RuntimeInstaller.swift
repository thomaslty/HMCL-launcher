import Foundation

/// Installs Java runtimes into the workspace and nowhere else.
public struct RuntimeInstaller: Sendable {
    private let workspace: Workspace
    private let downloader: any FileDownloading

    public init(workspace: Workspace, downloader: any FileDownloading) {
        self.workspace = workspace
        self.downloader = downloader
    }

    // MARK: - Install

    public func install(
        _ build: JavaBuild,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> JavaRuntime {
        let scratch = workspace.root.appending(path: "tmp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let archive = scratch.appending(path: "runtime.tar.gz")
        try await downloader.download(from: build.downloadURL, to: archive, onProgress: onProgress)

        guard try Checksum.sha1(ofFileAt: archive).caseInsensitiveCompare(build.sha1) == .orderedSame
        else {
            // Leave nothing half-installed for the next run to trip over.
            throw RuntimeInstallError.checksumMismatch
        }

        let unpacked = scratch.appending(path: "unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try extract(archive, into: unpacked)
        guard resolveJavaHome(in: unpacked) != nil else {
            throw RuntimeInstallError.javaHomeNotFound
        }

        let destination = workspace.runtimes.appending(path: build.runtimeID)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: workspace.runtimes,
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: unpacked, to: destination)

        guard let home = resolveJavaHome(in: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw RuntimeInstallError.javaHomeNotFound
        }
        return JavaRuntime(id: build.runtimeID, version: build.version, home: home)
    }

    // MARK: - Query and removal

    public func installed() -> [JavaRuntime] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: workspace.runtimes,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        return contents
            .compactMap { directory -> JavaRuntime? in
                guard directory.hasDirectoryPath,
                      let home = resolveJavaHome(in: directory)
                else { return nil }
                let id = directory.lastPathComponent
                let version = id.hasPrefix("liberica-")
                    ? String(id.dropFirst("liberica-".count))
                    : id
                return JavaRuntime(id: id, version: version, home: home)
            }
            .sorted { VersionOrder.newestFirst($0.version, $1.version) }
    }

    public func remove(_ runtime: JavaRuntime) throws {
        try FileManager.default.removeItem(at: workspace.runtimes.appending(path: runtime.id))
    }

    // MARK: - Archive handling

    private func extract(_ archive: URL, into directory: URL) throws {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path, "-C", directory.path]
        let errors = Pipe()
        tar.standardError = errors
        tar.standardOutput = Pipe()

        try tar.run()
        let message = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        tar.waitUntilExit()

        guard tar.terminationStatus == 0 else {
            throw RuntimeInstallError.extractionFailed(message.isEmpty ? "tar exited \(tar.terminationStatus)" : message)
        }
    }

    /// Liberica's macOS tarball unpacks to `jre-25.0.4-full.jre/bin/java`, while
    /// other vendors ship `something.jdk/Contents/Home/bin/java`. Look for the
    /// executable rather than assuming either shape.
    private func resolveJavaHome(in directory: URL, depth: Int = 0) -> URL? {
        guard depth <= 3 else { return nil }

        if FileManager.default.isExecutableFile(atPath: directory.appending(path: "bin/java").path) {
            return directory
        }
        let bundleHome = directory.appending(path: "Contents/Home")
        if FileManager.default.isExecutableFile(atPath: bundleHome.appending(path: "bin/java").path) {
            return bundleHome
        }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        for child in children where child.hasDirectoryPath {
            if let home = resolveJavaHome(in: child, depth: depth + 1) {
                return home
            }
        }
        return nil
    }
}
