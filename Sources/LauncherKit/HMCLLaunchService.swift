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
    /// java started and stopped before HMCL could, which is what a rejected JVM
    /// option looks like. `output` is the tail of the child's log.
    case exitedImmediately(status: Int32, output: String)
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
            logFile: workspace.logs.appending(path: "hmcl-\(Self.timestamp())-\(Self.suffix()).log")
        )
    }

    /// Starts HMCL, then checks once that it is still alive.
    ///
    /// No pipes are attached. stdout and stderr go straight to a file, because a
    /// pipe would tie the child's lifetime to ours — the whole point is that
    /// HMCL and Minecraft keep running after this app quits. macOS reparents the
    /// child to launchd on exit.
    ///
    /// The liveness check exists because a rejected JVM option kills java before
    /// HMCL starts, and without it the app would report a pid that is already
    /// gone. A rejected option exits at once while HMCL's own banner takes about
    /// 1.5 s, so one look after 800 ms tells the two apart. The check reads the
    /// log file we already redirect to, so it introduces no pipe.
    @discardableResult
    public func launch(
        runtime: JavaRuntime?,
        launcher: InstalledLauncher?,
        javaOptions: [String] = [],
        offlineAccountsEnabled: Bool = false,
        livenessDelay: Duration = .milliseconds(800)
    ) async throws -> RunningHMCL {
        let plan = try plan(
            runtime: runtime,
            launcher: launcher,
            javaOptions: javaOptions,
            offlineAccountsEnabled: offlineAccountsEnabled
        )

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

        // Sampled across the window rather than read once at the end. Foundation
        // notices a child's exit asynchronously, so a single late look can still
        // say "running" for a process that died milliseconds after spawning.
        if await died(process, within: livenessDelay) {
            throw LaunchError.exitedImmediately(
                status: process.terminationStatus,
                output: Self.tail(of: plan.logFile)
            )
        }

        return RunningHMCL(processIdentifier: process.processIdentifier, logFile: plan.logFile)
    }

    /// True when the child stopped at some point inside the window.
    private func died(_ process: Process, within window: Duration) async -> Bool {
        let step = Duration.milliseconds(50)
        var waited = Duration.zero
        while waited < window {
            try? await Task.sleep(for: step)
            waited += step
            if !process.isRunning { return true }
        }
        return !process.isRunning
    }

    /// The last few lines of the child's log, which for a rejected option is the
    /// JVM's own complaint and the only thing worth showing the user.
    static func tail(of logFile: URL, lines: Int = 12) -> String {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8) else { return "" }
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        return all.suffix(lines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The timestamp only has second resolution, so two launches in the same
    /// second would share a log file and the second would truncate the first's
    /// output. Found by running two launches at once.
    private static func suffix() -> String {
        String(UUID().uuidString.prefix(4)).lowercased()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
