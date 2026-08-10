import Foundation
import Testing

@testable import LauncherKit

private func makeWorkspace() -> Workspace {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "hmcl-ws-\(UUID().uuidString)")
    let workspace = Workspace(root: root)
    try? workspace.createDirectories()
    return workspace
}

private func makeRuntime(in workspace: Workspace, script: String) throws -> JavaRuntime {
    let home = workspace.runtimes.appending(path: "liberica-1.0.0")
    let bin = home.appending(path: "bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let java = bin.appending(path: "java")
    try Data(script.utf8).write(to: java)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
    return JavaRuntime(id: "liberica-1.0.0", version: "1.0.0", home: home)
}

private func makeJar(in workspace: Workspace) throws -> InstalledLauncher {
    let url = workspace.launchers.appending(path: "HMCL-3.16.3.jar")
    try Data("fake".utf8).write(to: url)
    return InstalledLauncher(version: "3.16.3", jarURL: url)
}

/// What java actually prints when it rejects an option.
private let rejectedOption = """
#!/bin/sh
echo "Unrecognized VM option 'BogusOption=1'"
echo "Error: Could not create the Java Virtual Machine."
exit 1
"""

@Suite struct EarlyExitTests {
    @Test func aChildThatKeepsRunningIsReportedAsStarted() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeRuntime(in: workspace, script: "#!/bin/sh\nsleep 5\n")
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let running = try await service.launch(
            runtime: runtime,
            launcher: try makeJar(in: workspace),
            livenessDelay: .milliseconds(800)
        )

        #expect(running.processIdentifier > 0)
        kill(running.processIdentifier, SIGTERM)
    }

    @Test func aChildThatDiesImmediatelyIsReportedAsFailed() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeRuntime(in: workspace, script: rejectedOption)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        var thrown: LaunchError?
        do {
            _ = try await service.launch(
                runtime: runtime,
                launcher: try makeJar(in: workspace),
                javaOptions: ["-XX:BogusOption=1"],
                livenessDelay: .milliseconds(800)
            )
        } catch let error as LaunchError {
            thrown = error
        }

        guard case .exitedImmediately(let status, let output) = thrown else {
            Issue.record("expected exitedImmediately, got \(String(describing: thrown))")
            return
        }
        #expect(status == 1)
        #expect(output.contains("Unrecognized VM option"))
        #expect(output.contains("Could not create the Java Virtual Machine"))
    }

    @Test func theFailureOutputComesFromTheRedirectedLogFileNotAPipe() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeRuntime(in: workspace, script: rejectedOption)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        _ = try? await service.launch(
            runtime: runtime,
            launcher: try makeJar(in: workspace),
            livenessDelay: .milliseconds(800)
        )

        // The same text must be on disk, which is only true if stdio was
        // redirected to a file rather than read through a pipe.
        let logs = try FileManager.default.contentsOfDirectory(atPath: workspace.logs.path)
        let log = logs.first { $0.hasPrefix("hmcl-") }
        #expect(log != nil)
        let text = try String(contentsOf: workspace.logs.appending(path: log ?? ""), encoding: .utf8)
        #expect(text.contains("Unrecognized VM option"))
    }

    @Test func aMissingRuntimeStillFailsBeforeSpawning() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        await #expect(throws: LaunchError.noRuntimeInstalled) {
            try await service.launch(runtime: nil, launcher: try makeJar(in: workspace))
        }
    }
}
