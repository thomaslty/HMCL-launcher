import Foundation

/// Everything needed to start HMCL, assembled before anything is spawned so it
/// can be asserted on without running a process.
public struct LaunchPlan: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL
    public let logFile: URL
}

/// A launch that has already happened.
public struct RunningHMCL: Sendable, Equatable {
    public let processIdentifier: Int32
    public let logFile: URL
}

public enum LaunchError: Error, Equatable {
    case noRuntimeInstalled
    case jarMissing
    case spawnFailed(String)
}

public struct HMCLLaunchService: Sendable {
    /// Any request to this fails immediately, which is how HMCL's update check
    /// is switched off. There is no documented flag for it; `Metadata.java`
    /// reads this property for the update endpoint.
    static let disabledUpdateSource = "https://127.0.0.1:1/updates-disabled"

    private let workspace: Workspace
    private let homeDirectory: URL

    public init(workspace: Workspace, homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.workspace = workspace
        self.homeDirectory = homeDirectory
    }

    /// The property HMCL reads to decide whether to hide offline login.
    /// `AccountListPage.java:65` in v3.16.3, inside a static initializer — which
    /// is why it has to be on the command line rather than set later.
    static let offlineRestrictionProperty = "hmcl.offline.auth.restricted"

    public func plan(
        runtime: JavaRuntime?,
        launcher: InstalledLauncher?,
        javaOptions: [String] = [],
        offlineAccountsEnabled: Bool = false
    ) throws -> LaunchPlan {
        guard let runtime,
              FileManager.default.isExecutableFile(atPath: runtime.javaExecutable.path)
        else {
            throw LaunchError.noRuntimeInstalled
        }
        guard let launcher,
              FileManager.default.fileExists(atPath: launcher.jarURL.path)
        else {
            throw LaunchError.jarMissing
        }

        var environment = ProcessInfo.processInfo.environment
        // The three variables HMCL's Metadata.java reads. Pointing them here is
        // what keeps HMCL's own downloads — including the Java runtimes it
        // fetches for the game — inside our folder.
        environment["HMCL_USER_HOME"] = workspace.hmclUserHome.path
        environment["HMCL_LOCAL_HOME"] = workspace.hmclLocalHome.path
        environment["HMCL_DEPENDENCIES_DIR"] = workspace.hmclDependencies.path

        // Ours first, the user's last. The JVM takes the last -D for a given key,
        // so anything typed by hand overrides what we set — including the update
        // source. Nothing typed here is filtered.
        var arguments = ["-Dhmcl.update_source.override=\(Self.disabledUpdateSource)"]

        let offlinePrefix = "-D\(Self.offlineRestrictionProperty)="
        if offlineAccountsEnabled, !javaOptions.contains(where: { $0.hasPrefix(offlinePrefix) }) {
            arguments.append("\(offlinePrefix)false")
        }

        arguments += javaOptions
        arguments += ["-jar", launcher.jarURL.path]

        return LaunchPlan(
            executable: runtime.javaExecutable,
            arguments: arguments,
            environment: environment,
            // HMCL resolves its game directory as ".minecraft" relative to the
            // working directory, so running from home puts saves in the shared
            // ~/.minecraft rather than burying them inside the app folder.
            workingDirectory: homeDirectory,
            logFile: workspace.logs.appending(path: "hmcl-\(Self.timestamp()).log")
        )
    }

    /// Starts HMCL and returns immediately.
    ///
    /// No pipes are attached. stdout and stderr go straight to a file, because a
    /// pipe would tie the child's lifetime to ours — the whole point is that
    /// HMCL and Minecraft keep running after this app quits. macOS reparents the
    /// child to launchd on exit.
    @discardableResult
    public func launch(runtime: JavaRuntime?, launcher: InstalledLauncher?) throws -> RunningHMCL {
        let plan = try plan(runtime: runtime, launcher: launcher)

        try FileManager.default.createDirectory(at: workspace.logs, withIntermediateDirectories: true)
        for directory in [workspace.hmclUserHome, workspace.hmclLocalHome, workspace.hmclDependencies] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: plan.logFile.path, contents: nil)

        guard let log = try? FileHandle(forWritingTo: plan.logFile) else {
            throw LaunchError.spawnFailed("could not open \(plan.logFile.lastPathComponent)")
        }

        let process = Process()
        process.executableURL = plan.executable
        process.arguments = plan.arguments
        process.environment = plan.environment
        process.currentDirectoryURL = plan.workingDirectory
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            try? log.close()
            throw LaunchError.spawnFailed(error.localizedDescription)
        }

        // Our copy of the write end is no longer needed; the child holds its own.
        try? log.close()

        return RunningHMCL(processIdentifier: process.processIdentifier, logFile: plan.logFile)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
