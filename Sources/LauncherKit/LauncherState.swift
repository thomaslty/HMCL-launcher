import Foundation

public enum UIMode: String, Codable, Sendable, CaseIterable {
    case simple
    case advanced
}

/// What the app remembers between runs.
public struct LauncherState: Codable, Sendable, Equatable {
    public var mode: UIMode
    public var selectedLauncherVersion: String?
    public var selectedRuntimeID: String?

    public init(
        mode: UIMode = .simple,
        selectedLauncherVersion: String? = nil,
        selectedRuntimeID: String? = nil
    ) {
        self.mode = mode
        self.selectedLauncherVersion = selectedLauncherVersion
        self.selectedRuntimeID = selectedRuntimeID
    }
}

/// Reads and writes `state.json`.
///
/// Loading never throws. A missing or unreadable file means a first run or a
/// file someone edited by hand, and neither is worth blocking the app over —
/// both fall back to defaults.
public struct StateStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> LauncherState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(LauncherState.self, from: data)
        else {
            return LauncherState()
        }
        return state
    }

    public func save(_ state: LauncherState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
