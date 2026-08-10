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

private func makeRuntime(in workspace: Workspace, script: String = "#!/bin/sh\n") throws -> JavaRuntime {
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

private let offlinePrefix = "-Dhmcl.offline.auth.restricted="

@Suite struct LaunchOptionsTests {
    @Test func extraOptionsAppearInOrderBeforeTheJar() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(
            runtime: try makeRuntime(in: workspace),
            launcher: try makeJar(in: workspace),
            javaOptions: ["-Xmx4G", "-Dfoo=bar"]
        )

        let jarIndex = plan.arguments.firstIndex(of: "-jar")!
        let heap = plan.arguments.firstIndex(of: "-Xmx4G")!
        let foo = plan.arguments.firstIndex(of: "-Dfoo=bar")!
        #expect(heap < foo)
        #expect(foo < jarIndex)
    }

    @Test func noExtraOptionsChangesNothing() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(
            runtime: try makeRuntime(in: workspace),
            launcher: try makeJar(in: workspace)
        )

        #expect(!plan.arguments.contains { $0.hasPrefix(offlinePrefix) })
    }

    @Test func enablingOfflineAccountsAddsTheFlag() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(
            runtime: try makeRuntime(in: workspace),
            launcher: try makeJar(in: workspace),
            offlineAccountsEnabled: true
        )

        #expect(plan.arguments.contains("-Dhmcl.offline.auth.restricted=false"))
    }

    @Test func aTypedValueWinsOverTheToggle() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(
            runtime: try makeRuntime(in: workspace),
            launcher: try makeJar(in: workspace),
            javaOptions: ["-Dhmcl.offline.auth.restricted=true"],
            offlineAccountsEnabled: true
        )

        let offlineArguments = plan.arguments.filter { $0.hasPrefix(offlinePrefix) }
        #expect(offlineArguments == ["-Dhmcl.offline.auth.restricted=true"])
    }

    @Test func typedOptionsComeLastSoADuplicatePropertyWins() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(
            runtime: try makeRuntime(in: workspace),
            launcher: try makeJar(in: workspace),
            javaOptions: ["-Dhmcl.update_source.override=https://example.invalid/real"]
        )

        // The JVM takes the last -D for a given key, so ours has to come first
        // for a typed one to override it.
        let ours = plan.arguments.firstIndex { $0.hasPrefix("-Dhmcl.update_source.override=") }!
        let theirs = plan.arguments.lastIndex { $0.hasPrefix("-Dhmcl.update_source.override=") }!
        #expect(ours < theirs)
    }

    @Test func optionsWeWouldNeverRecommendArePassedAnyway() throws {
        let workspace = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let service = HMCLLaunchService(workspace: workspace, homeDirectory: workspace.root)

        let plan = try service.plan(
            runtime: try makeRuntime(in: workspace),
            launcher: try makeJar(in: workspace),
            javaOptions: ["-XX:BogusOption=1"]
        )

        #expect(plan.arguments.contains("-XX:BogusOption=1"))
    }
}
