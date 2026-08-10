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

/// A runtime whose `bin/java` is a shell script, so a launch can be observed
/// without a 126 MB JRE.
private func makeFakeRuntime(in workspace: Workspace, script: String) throws -> JavaRuntime {
    let home = workspace.runtimes.appending(path: "liberica-1.0.0")
    let bin = home.appending(path: "bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let java = bin.appending(path: "java")
    try Data(script.utf8).write(to: java)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
    return JavaRuntime(id: "liberica-1.0.0", version: "1.0.0", home: home)
}

private func makeFakeJar(in workspace: Workspace, version: String = "3.16.3") throws -> InstalledLauncher {
    let url = workspace.launchers.appending(path: "HMCL-\(version).jar")
    try Data("fake".utf8).write(to: url)
    return InstalledLauncher(version: version, jarURL: url)
}

@Suite struct HMCLLaunchServiceTests {
    @Test func planRunsTheRuntimeJavaAgainstTheSelectedJar() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeFakeRuntime(in: workspace, script: "#!/bin/sh\n")
        let jar = try makeFakeJar(in: workspace)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(runtime: runtime, launcher: jar)

        #expect(plan.executable == runtime.javaExecutable)
        #expect(plan.arguments.contains("-jar"))
        #expect(plan.arguments.contains(jar.jarURL.path))
    }

    @Test func planPointsHMCLsOwnDirectoriesIntoTheWorkspace() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeFakeRuntime(in: workspace, script: "#!/bin/sh\n")
        let jar = try makeFakeJar(in: workspace)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(runtime: runtime, launcher: jar)

        #expect(plan.environment["HMCL_USER_HOME"] == workspace.hmclUserHome.path)
        #expect(plan.environment["HMCL_LOCAL_HOME"] == workspace.hmclLocalHome.path)
        #expect(plan.environment["HMCL_DEPENDENCIES_DIR"] == workspace.hmclDependencies.path)
    }

    @Test func planInheritsTheSurroundingEnvironment() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeFakeRuntime(in: workspace, script: "#!/bin/sh\n")
        let jar = try makeFakeJar(in: workspace)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(runtime: runtime, launcher: jar)

        #expect(plan.environment["PATH"] != nil)
    }

    @Test func planWorksFromTheUsersHomeSoSavesStayShared() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeFakeRuntime(in: workspace, script: "#!/bin/sh\n")
        let jar = try makeFakeJar(in: workspace)
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: home)

        let plan = try service.plan(runtime: runtime, launcher: jar)

        // HMCL resolves its game directory as .minecraft relative to the working
        // directory, so this is what decides where saves land.
        #expect(plan.workingDirectory == home)
    }

    @Test func planSuppressesHMCLSelfUpdate() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeFakeRuntime(in: workspace, script: "#!/bin/sh\n")
        let jar = try makeFakeJar(in: workspace)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(runtime: runtime, launcher: jar)

        #expect(plan.arguments.contains { $0.hasPrefix("-Dhmcl.update_source.override=") })
    }

    @Test func planLogsIntoTheWorkspaceLogsDirectory() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeFakeRuntime(in: workspace, script: "#!/bin/sh\n")
        let jar = try makeFakeJar(in: workspace)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(runtime: runtime, launcher: jar)

        #expect(plan.logFile.deletingLastPathComponent().path == workspace.logs.path)
        #expect(plan.logFile.lastPathComponent.hasPrefix("hmcl-"))
    }

    @Test func launchingWithoutARuntimeFails() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let jar = try makeFakeJar(in: workspace)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        #expect(throws: LaunchError.noRuntimeInstalled) {
            try service.plan(runtime: nil, launcher: jar)
        }
    }

    @Test func launchingWithoutAJarFails() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeFakeRuntime(in: workspace, script: "#!/bin/sh\n")
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        #expect(throws: LaunchError.jarMissing) {
            try service.plan(runtime: runtime, launcher: nil)
        }
    }

    @Test func launchingWithAJarThatWasDeletedFails() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let runtime = try makeFakeRuntime(in: workspace, script: "#!/bin/sh\n")
        let jar = try makeFakeJar(in: workspace)
        try FileManager.default.removeItem(at: jar.jarURL)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        #expect(throws: LaunchError.jarMissing) {
            try service.plan(runtime: runtime, launcher: jar)
        }
    }

    @Test func launchRedirectsChildOutputIntoTheLogFile() async throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        // Stays alive, because a child that exits at once is now reported as a
        // failed launch — see EarlyExitTests.
        let runtime = try makeFakeRuntime(
            in: workspace,
            script: "#!/bin/sh\necho \"args: $*\"\necho \"user home: $HMCL_USER_HOME\"\nsleep 5\n"
        )
        let jar = try makeFakeJar(in: workspace)
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let running = try await service.launch(
            runtime: runtime,
            launcher: jar,
            livenessDelay: .milliseconds(200)
        )
        #expect(running.processIdentifier > 0)

        let contents = try await waitForFile(running.logFile)
        #expect(contents.contains("-jar"))
        #expect(contents.contains(workspace.hmclUserHome.path))
        kill(running.processIdentifier, SIGTERM)
    }

    private func waitForFile(_ url: URL, attempts: Int = 200) async throws -> String {
        for _ in 0..<attempts {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return String(decoding: data, as: UTF8.self)
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return ""
    }
}
