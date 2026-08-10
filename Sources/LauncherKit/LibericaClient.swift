import Foundation

/// Resolves the newest LTS Liberica **Full** JRE for Apple Silicon.
///
/// "Full" is the whole point: those builds have JavaFX compiled in, so HMCL
/// finds it on the boot module path instead of downloading OpenJFX and
/// module-patching it at startup — the most commonly reported macOS failure.
public struct LibericaClient: Sendable {
    private let fetcher: any HTTPFetching

    public init(fetcher: any HTTPFetching) {
        self.fetcher = fetcher
    }

    public func latestLTSFullJRE() async throws -> JavaBuild {
        var components = URLComponents(string: "https://api.bell-sw.com/v1/liberica/releases")!
        components.queryItems = [
            URLQueryItem(name: "os", value: "macos"),
            URLQueryItem(name: "arch", value: "arm"),
            URLQueryItem(name: "bitness", value: "64"),
            URLQueryItem(name: "package-type", value: "tar.gz"),
            URLQueryItem(name: "bundle-type", value: "jre-full"),
            URLQueryItem(name: "release-type", value: "lts"),
            URLQueryItem(name: "version-modifier", value: "latest"),
        ]

        let response = try await fetcher.get(
            components.url!,
            headers: ["Accept": "application/json"]
        )
        guard response.status == 200 else {
            throw RuntimeInstallError.unexpectedStatus(response.status)
        }

        let builds = try JSONDecoder().decode([APIBuild].self, from: response.body)
        guard let newest = builds.sorted(by: { VersionOrder.newestFirst($0.version, $1.version) }).first
        else {
            throw RuntimeInstallError.noBuildAvailable
        }
        return JavaBuild(version: newest.version, downloadURL: newest.downloadUrl, sha1: newest.sha1)
    }

    private struct APIBuild: Decodable {
        let version: String
        let downloadUrl: URL
        let sha1: String
    }
}
