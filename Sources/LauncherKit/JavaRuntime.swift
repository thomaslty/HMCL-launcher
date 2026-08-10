import Foundation

/// A Liberica build the app could install.
public struct JavaBuild: Sendable, Equatable {
    public let version: String
    public let downloadURL: URL
    public let sha1: String

    public init(version: String, downloadURL: URL, sha1: String) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha1 = sha1
    }

    /// Doubles as the directory name under `runtimes/`.
    public var runtimeID: String { "liberica-\(version)" }
}

/// A Java runtime installed in the workspace.
public struct JavaRuntime: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let version: String
    /// The directory holding `bin/java`. Liberica's macOS tarball unpacks to a
    /// flat layout, other vendors ship a `Contents/Home` bundle, so this is
    /// resolved rather than assumed.
    public let home: URL

    public init(id: String, version: String, home: URL) {
        self.id = id
        self.version = version
        self.home = home
    }

    public var javaExecutable: URL { home.appending(path: "bin/java") }

    /// "Liberica 25.0.4+9" — what the Advanced-mode picker shows.
    public var displayName: String {
        id.hasPrefix("liberica-") ? "Liberica \(version)" : "\(id) \(version)"
    }
}

public enum RuntimeInstallError: Error, Equatable {
    case noBuildAvailable
    case checksumMismatch
    case extractionFailed(String)
    case javaHomeNotFound
    case unexpectedStatus(Int)
}
