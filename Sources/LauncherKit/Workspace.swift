import Foundation

/// Every file this launcher downloads lives under one directory in Application
/// Support. That is what keeps a system Java untouched: nothing here is ever
/// written to /Library/Java/JavaVirtualMachines, to PATH, or to a shell profile.
///
/// Application Support rather than the app bundle, because writing inside
/// Contents/Resources breaks the code signature and gets wiped on every update.
public struct Workspace: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/net.tlau.HMCLLauncher`
    public static func applicationSupport() throws -> Workspace {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return Workspace(root: base.appending(path: AppIdentity.bundleIdentifier))
    }

    /// Extracted Java runtimes, one directory per installed version.
    public var runtimes: URL { root.appending(path: "runtimes") }

    /// Downloaded `HMCL-<version>.jar` files.
    public var launchers: URL { root.appending(path: "launchers") }

    /// Handed to HMCL as `HMCL_USER_HOME` — its config, accounts, and the Java
    /// runtimes it downloads for the game itself.
    public var hmclUserHome: URL { root.appending(path: "hmcl-home") }

    /// Handed to HMCL as `HMCL_LOCAL_HOME`.
    public var hmclLocalHome: URL { root.appending(path: "hmcl-local") }

    /// Handed to HMCL as `HMCL_DEPENDENCIES_DIR` — its JavaFX and library cache.
    public var hmclDependencies: URL { root.appending(path: "hmcl-deps") }

    /// Our own log plus the redirected stdout/stderr of each HMCL run.
    public var logs: URL { root.appending(path: "logs") }

    public var stateFile: URL { root.appending(path: "state.json") }
    public var releaseCacheFile: URL { root.appending(path: "release-cache.json") }

    public var allDirectories: [URL] {
        [root, runtimes, launchers, hmclUserHome, hmclLocalHome, hmclDependencies, logs]
    }

    public var allPaths: [URL] {
        allDirectories + [stateFile, releaseCacheFile]
    }

    /// Creates anything missing. Running it again does nothing.
    public func createDirectories() throws {
        for directory in allDirectories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
