import AppKit
import Foundation
import LauncherKit
import SwiftUI

/// Renders the real SwiftUI views to PNG.
///
/// `screencapture` needs Screen Recording permission, which a build machine or
/// CI runner will not have. This draws the same views through ImageRenderer
/// instead, so every change can be looked at.
///
///     HMCL\ Launcher.app/Contents/MacOS/HMCLLauncher --render-screenshots <dir>
@MainActor
enum ScreenshotRenderer {
    static func requestedDirectory() -> URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-screenshots"),
              arguments.index(after: flag) < arguments.endIndex
        else { return nil }
        return URL(fileURLWithPath: arguments[arguments.index(after: flag)])
    }

    /// `--live` draws the app's real state — whatever is actually installed in
    /// the workspace — instead of the fixtures. That is what makes a screenshot
    /// evidence rather than a mock-up.
    static var wantsLiveState: Bool {
        CommandLine.arguments.contains("--live")
    }

    static func renderAll(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // AppKit controls need an initialised application before they will draw.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        if wantsLiveState {
            renderLive(into: directory)
            return
        }

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            render(model: readyModel(mode: .simple), scheme: scheme, to: directory.appending(path: "simple-\(suffix).png"))
            render(model: readyModel(mode: .advanced), scheme: scheme, to: directory.appending(path: "advanced-\(suffix).png"))
            render(model: coldModel(), scheme: scheme, to: directory.appending(path: "cold-start-\(suffix).png"))
            render(model: failedModel(), scheme: scheme, to: directory.appending(path: "failed-launch-\(suffix).png"))
        }

        FileHandle.standardOutput.write(Data("rendered screenshots into \(directory.path)\n".utf8))
    }

    private static func renderLive(into directory: URL) {
        guard let workspace = try? Workspace.applicationSupport() else {
            FileHandle.standardError.write(Data("no workspace\n".utf8))
            return
        }
        let model = LauncherViewModel(workspace: workspace)

        // Pump the main run loop so the version check can finish before drawing.
        let finished = Flag()
        Task { @MainActor in
            await model.refreshLatest()
            finished.value = true
        }
        let deadline = Date().addingTimeInterval(15)
        while !finished.value, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        for mode in [UIMode.simple, .advanced] {
            model.mode = mode
            render(model: model, scheme: .light, to: directory.appending(path: "live-\(mode.rawValue).png"))
        }
        FileHandle.standardOutput.write(Data("rendered live state into \(directory.path)\n".utf8))
    }

    private final class Flag: @unchecked Sendable {
        var value = false
    }

    // MARK: - Fixtures

    private static func previewWorkspace() -> Workspace {
        Workspace(
            root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "hmcl-screenshots-\(UUID().uuidString)")
        )
    }

    private static func readyModel(mode: UIMode) -> LauncherViewModel {
        let workspace = previewWorkspace()
        let start = Date(timeIntervalSince1970: 1_770_000_000)
        return LauncherViewModel(
            preview: .init(
                workspace: workspace,
                mode: mode,
                latestVersion: "3.16.3",
                latestNote: nil,
                launchers: [
                    InstalledLauncher(version: "3.16.3", jarURL: workspace.launchers.appending(path: "HMCL-3.16.3.jar")),
                    InstalledLauncher(version: "3.16.2", jarURL: workspace.launchers.appending(path: "HMCL-3.16.2.jar")),
                ],
                runtimes: [
                    JavaRuntime(id: "liberica-25.0.4+9", version: "25.0.4+9", home: workspace.runtimes.appending(path: "liberica-25.0.4+9")),
                    JavaRuntime(id: "liberica-21.0.5+11", version: "21.0.5+11", home: workspace.runtimes.appending(path: "liberica-21.0.5+11")),
                ],
                events: [
                    LogEvent(at: start, message: "Latest release is 3.16.3"),
                    LogEvent(at: start.addingTimeInterval(1), message: "Java options: -Xmx4G"),
                    LogEvent(at: start.addingTimeInterval(1), message: "Offline accounts allowed"),
                    LogEvent(at: start.addingTimeInterval(2), message: "HMCL started, process 4412"),
                    LogEvent(at: start.addingTimeInterval(2), message: "Output goes to hmcl-2026-08-09T23-45-22.log"),
                ],
                customJavaOptions: "-Xmx4G"
            )
        )
    }

    /// A launch killed by a rejected option — the case the liveness check exists
    /// for, and the one worth being able to look at.
    private static func failedModel() -> LauncherViewModel {
        let workspace = previewWorkspace()
        let start = Date(timeIntervalSince1970: 1_770_000_000)
        return LauncherViewModel(
            preview: .init(
                workspace: workspace,
                mode: .advanced,
                latestVersion: "3.16.3",
                latestNote: nil,
                launchers: [
                    InstalledLauncher(version: "3.16.3", jarURL: workspace.launchers.appending(path: "HMCL-3.16.3.jar"))
                ],
                runtimes: [
                    JavaRuntime(id: "liberica-25.0.4+9", version: "25.0.4+9", home: workspace.runtimes.appending(path: "liberica-25.0.4+9"))
                ],
                events: [
                    LogEvent(at: start, message: "Java options: -XX:BogusOption=1"),
                    LogEvent(at: start.addingTimeInterval(1), message: "Java exited with status 1"),
                    LogEvent(at: start.addingTimeInterval(1), message: "Unrecognized VM option 'BogusOption=1'"),
                    LogEvent(at: start.addingTimeInterval(1), message: "Error: Could not create the Java Virtual Machine."),
                ],
                customJavaOptions: "-XX:BogusOption=1"
            )
        )
    }

    private static func coldModel() -> LauncherViewModel {
        LauncherViewModel(
            preview: .init(
                workspace: previewWorkspace(),
                mode: .simple,
                latestVersion: "3.16.3",
                latestNote: nil,
                launchers: [],
                runtimes: [],
                events: [],
                // Off here on purpose, so a screenshot covers both switch states.
                offlineAccountsEnabled: false
            )
        )
    }

    // MARK: - Rendering

    /// Draws through an offscreen window rather than `ImageRenderer`.
    ///
    /// ImageRenderer cannot rasterize AppKit-backed controls — segmented
    /// pickers, pop-up buttons and borderless buttons all come out as blank
    /// placeholders. Hosting the view in a real window and calling
    /// `cacheDisplay` draws the genuine controls, and because the app is
    /// drawing its own view hierarchy it needs no Screen Recording permission.
    private static func render(model: LauncherViewModel, scheme: ColorScheme, to url: URL) {
        let hosting = NSHostingView(rootView: LauncherShell(model: model))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.layoutIfNeeded()
        window.displayIfNeeded()

        // AppKit controls that animate into position — NSSwitch moves its knob —
        // draw their starting state if captured immediately, which made an "on"
        // switch photograph as "off". Let the run loop settle first.
        let settle = Date().addingTimeInterval(0.4)
        while Date() < settle {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        window.displayIfNeeded()

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write(Data("could not allocate bitmap for \(url.lastPathComponent)\n".utf8))
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not encode \(url.lastPathComponent)\n".utf8))
            return
        }
        try? png.write(to: url)
    }
}
