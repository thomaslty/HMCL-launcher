import AppKit
import Foundation
import LauncherKit
import Observation

struct LogEvent: Identifiable, Equatable {
    let id = UUID()
    let at: Date
    let message: String

    var time: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: at)
    }
}

@MainActor
@Observable
final class LauncherViewModel {
    enum Activity: Equatable {
        case idle
        case checking
        case installingRuntime(Double)
        case installingLauncher(Double)
        case starting

        var isBusy: Bool { self != .idle }
    }

    // MARK: - Published state

    var mode: UIMode {
        didSet { persist() }
    }

    private(set) var latestVersion: String?
    private(set) var latestNote: String?
    private(set) var installedLaunchers: [InstalledLauncher] = []
    private(set) var installedRuntimes: [JavaRuntime] = []
    private(set) var activity: Activity = .idle
    private(set) var events: [LogEvent] = []
    private(set) var problem: String?

    var selectedLauncher: InstalledLauncher? {
        didSet { persist() }
    }

    var selectedRuntime: JavaRuntime? {
        didSet { persist() }
    }

    // MARK: - Collaborators

    private let workspace: Workspace
    private let stateStore: StateStore
    private let releases: GitHubReleaseClient
    private let liberica: LibericaClient
    private let runtimeInstaller: RuntimeInstaller
    private let launcherInstaller: LauncherInstaller
    private let launchService: HMCLLaunchService

    // MARK: - Setup

    init(workspace: Workspace) {
        self.workspace = workspace
        try? workspace.createDirectories()

        let fetcher = URLSessionFetcher()
        let downloader = URLSessionDownloader()

        stateStore = StateStore(url: workspace.stateFile)
        releases = GitHubReleaseClient(fetcher: fetcher, cacheURL: workspace.releaseCacheFile)
        liberica = LibericaClient(fetcher: fetcher)
        runtimeInstaller = RuntimeInstaller(workspace: workspace, downloader: downloader)
        launcherInstaller = LauncherInstaller(workspace: workspace, downloader: downloader)
        launchService = HMCLLaunchService(workspace: workspace)

        let saved = stateStore.load()
        mode = saved.mode
        refreshInstalled()
        selectedLauncher = installedLaunchers.first { $0.version == saved.selectedLauncherVersion }
            ?? installedLaunchers.first
        selectedRuntime = installedRuntimes.first { $0.id == saved.selectedRuntimeID }
            ?? installedRuntimes.first
    }

    /// Used by the screenshot renderer to show a populated window without
    /// touching the network or the real workspace.
    init(preview: Preview) {
        workspace = preview.workspace
        stateStore = StateStore(url: preview.workspace.stateFile)
        let fetcher = URLSessionFetcher()
        let downloader = URLSessionDownloader()
        releases = GitHubReleaseClient(fetcher: fetcher, cacheURL: preview.workspace.releaseCacheFile)
        liberica = LibericaClient(fetcher: fetcher)
        runtimeInstaller = RuntimeInstaller(workspace: preview.workspace, downloader: downloader)
        launcherInstaller = LauncherInstaller(workspace: preview.workspace, downloader: downloader)
        launchService = HMCLLaunchService(workspace: preview.workspace)

        mode = preview.mode
        latestVersion = preview.latestVersion
        latestNote = preview.latestNote
        installedLaunchers = preview.launchers
        installedRuntimes = preview.runtimes
        selectedLauncher = preview.launchers.first
        selectedRuntime = preview.runtimes.first
        events = preview.events
    }

    struct Preview {
        var workspace: Workspace
        var mode: UIMode
        var latestVersion: String?
        var latestNote: String?
        var launchers: [InstalledLauncher]
        var runtimes: [JavaRuntime]
        var events: [LogEvent]
    }

    // MARK: - Derived

    var hasLauncher: Bool { selectedLauncher != nil }
    var hasRuntime: Bool { selectedRuntime != nil }
    var isReady: Bool { hasLauncher && hasRuntime }

    /// Only shown while something is still missing, so the first-run download is
    /// never a surprise.
    var downloadNotice: String? {
        guard !activity.isBusy else { return nil }
        switch (hasLauncher, hasRuntime) {
        case (true, true): return nil
        case (true, false): return "Start downloads Java, about 126 MB."
        case (false, true): return "Start downloads HMCL, about 10 MB."
        case (false, false): return "Start downloads HMCL and Java, about 136 MB."
        }
    }

    var startButtonTitle: String {
        switch activity {
        case .idle: return isReady ? "Start" : "Download and start"
        case .checking: return "Checking for updates…"
        case .installingRuntime(let fraction): return "Downloading Java… \(percent(fraction))"
        case .installingLauncher(let fraction): return "Downloading HMCL… \(percent(fraction))"
        case .starting: return "Starting HMCL…"
        }
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // MARK: - Actions

    func refreshLatest() async {
        activity = .checking
        defer { activity = .idle }
        do {
            let lookup = try await releases.latestRelease()
            latestVersion = lookup.release.version
            latestNote = lookup.source == .cache ? "cached" : nil
            log(lookup.source == .cache
                ? "Latest is \(lookup.release.version), from cache"
                : "Latest release is \(lookup.release.version)")
            problem = nil
        } catch ReleaseLookupError.rateLimited {
            problem = "GitHub rate limit reached. The version shows again within the hour."
            log("GitHub rate limit reached")
        } catch {
            problem = "Could not reach GitHub. Check your connection, then try again."
            log("Version check failed: \(error)")
        }
    }

    func start() async {
        problem = nil
        do {
            if !hasLauncher {
                try await installLatestLauncher()
            }
            if !hasRuntime {
                try await installLatestRuntime()
            }

            activity = .starting
            let running = try launchService.launch(runtime: selectedRuntime, launcher: selectedLauncher)
            log("HMCL started, process \(running.processIdentifier)")
            log("Output goes to \(running.logFile.lastPathComponent)")
        } catch {
            problem = describe(error)
            log("Start failed: \(error)")
        }
        activity = .idle
    }

    func reinstallSelectedLauncher() async {
        problem = nil
        do {
            try await installLatestLauncher()
        } catch {
            problem = describe(error)
            log("Download failed: \(error)")
        }
        activity = .idle
    }

    func reinstallSelectedRuntime() async {
        problem = nil
        do {
            try await installLatestRuntime()
        } catch {
            problem = describe(error)
            log("Download failed: \(error)")
        }
        activity = .idle
    }

    func deleteSelectedLauncher() {
        guard let launcher = selectedLauncher else { return }
        do {
            try launcherInstaller.remove(launcher)
            log("Removed HMCL \(launcher.version)")
            refreshInstalled()
            selectedLauncher = installedLaunchers.first
        } catch {
            problem = "Could not remove HMCL \(launcher.version)."
        }
    }

    func deleteSelectedRuntime() {
        guard let runtime = selectedRuntime else { return }
        do {
            try runtimeInstaller.remove(runtime)
            log("Removed \(runtime.displayName)")
            refreshInstalled()
            selectedRuntime = installedRuntimes.first
        } catch {
            problem = "Could not remove \(runtime.displayName)."
        }
    }

    func revealWorkspace() {
        NSWorkspace.shared.activateFileViewerSelecting([workspace.root])
    }

    // MARK: - Work

    private func installLatestLauncher() async throws {
        let lookup = try await releases.latestRelease()
        latestVersion = lookup.release.version
        log("Downloading HMCL \(lookup.release.version)")

        activity = .installingLauncher(0)
        let installed = try await launcherInstaller.install(lookup.release) { [weak self] fraction in
            Task { @MainActor in self?.activity = .installingLauncher(fraction) }
        }
        refreshInstalled()
        selectedLauncher = installed
        log("HMCL \(installed.version) ready")
    }

    private func installLatestRuntime() async throws {
        activity = .checking
        let build = try await liberica.latestLTSFullJRE()
        log("Downloading Liberica \(build.version), JavaFX included")

        activity = .installingRuntime(0)
        let installed = try await runtimeInstaller.install(build) { [weak self] fraction in
            Task { @MainActor in self?.activity = .installingRuntime(fraction) }
        }
        refreshInstalled()
        selectedRuntime = installed
        log("\(installed.displayName) ready")
    }

    private func refreshInstalled() {
        installedLaunchers = launcherInstaller.installed()
        installedRuntimes = runtimeInstaller.installed()
    }

    private func persist() {
        try? stateStore.save(
            LauncherState(
                mode: mode,
                selectedLauncherVersion: selectedLauncher?.version,
                selectedRuntimeID: selectedRuntime?.id
            )
        )
    }

    private func log(_ message: String) {
        events.append(LogEvent(at: Date(), message: message))
        if events.count > 500 {
            events.removeFirst(events.count - 500)
        }
    }

    private func describe(_ error: any Error) -> String {
        switch error {
        case LaunchError.noRuntimeInstalled:
            return "No Java runtime yet. Press Start and it downloads one."
        case LaunchError.jarMissing:
            return "That HMCL version is gone from disk. Download it again."
        case RuntimeInstallError.checksumMismatch:
            return "The Java download did not match its checksum and was discarded. Try again."
        case ReleaseLookupError.rateLimited:
            return "GitHub rate limit reached. Try again within the hour."
        default:
            return "\(error)"
        }
    }
}
