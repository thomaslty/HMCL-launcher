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
    /// Adds `-Dhmcl.offline.auth.restricted=false` at launch. On by default.
    public var offlineAccountsEnabled: Bool
    /// Passed to the JVM unchanged.
    public var customJavaOptions: String

    public init(
        mode: UIMode = .simple,
        selectedLauncherVersion: String? = nil,
        selectedRuntimeID: String? = nil,
        offlineAccountsEnabled: Bool = true,
        customJavaOptions: String = ""
    ) {
        self.mode = mode
        self.selectedLauncherVersion = selectedLauncherVersion
        self.selectedRuntimeID = selectedRuntimeID
        self.offlineAccountsEnabled = offlineAccountsEnabled
        self.customJavaOptions = customJavaOptions
    }

    /// Decoded field by field so a `state.json` written by an older version,
    /// which has none of the newer keys, keeps its mode and selections instead
    /// of failing to decode and being replaced with defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(UIMode.self, forKey: .mode) ?? .simple
        selectedLauncherVersion = try container.decodeIfPresent(String.self, forKey: .selectedLauncherVersion)
        selectedRuntimeID = try container.decodeIfPresent(String.self, forKey: .selectedRuntimeID)
        offlineAccountsEnabled = try container.decodeIfPresent(Bool.self, forKey: .offlineAccountsEnabled) ?? true
        customJavaOptions = try container.decodeIfPresent(String.self, forKey: .customJavaOptions) ?? ""
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
