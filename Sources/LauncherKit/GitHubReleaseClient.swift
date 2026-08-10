import Foundation

/// A published HMCL release and the jar we would download from it.
public struct HMCLRelease: Codable, Sendable, Equatable {
    public let version: String
    public let jarName: String
    public let jarURL: URL
    public let jarSize: Int

    public init(version: String, jarName: String, jarURL: URL, jarSize: Int) {
        self.version = version
        self.jarName = jarName
        self.jarURL = jarURL
        self.jarSize = jarSize
    }
}

public struct ReleaseLookup: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case network
        case cache
    }

    public let release: HMCLRelease
    public let source: Source
}

public enum ReleaseLookupError: Error, Equatable {
    /// The release exists but publishes no `HMCL-<version>.jar`.
    case noJarAsset
    /// GitHub allows 60 unauthenticated calls an hour and we have none left.
    case rateLimited
    case unexpectedStatus(Int)
    case malformedResponse
}

/// Reads the latest HMCL release from GitHub, remembering the ETag so repeated
/// launches revalidate instead of spending the hourly allowance.
public struct GitHubReleaseClient: Sendable {
    public static let defaultAPIURL = URL(
        string: "https://api.github.com/repos/HMCL-dev/HMCL/releases/latest"
    )!

    private let fetcher: any HTTPFetching
    private let cacheURL: URL
    private let apiURL: URL

    public init(fetcher: any HTTPFetching, cacheURL: URL, apiURL: URL = defaultAPIURL) {
        self.fetcher = fetcher
        self.cacheURL = cacheURL
        self.apiURL = apiURL
    }

    public func latestRelease() async throws -> ReleaseLookup {
        let cached = loadCache()

        var headers = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "\(AppIdentity.displayName)/\(AppIdentity.version)",
        ]
        if let etag = cached?.etag {
            headers["If-None-Match"] = etag
        }

        let response = try await fetcher.get(apiURL, headers: headers)

        switch response.status {
        case 200:
            let release = try parse(response.body)
            saveCache(Cache(etag: response.header("etag"), release: release))
            return ReleaseLookup(release: release, source: .network)

        case 304:
            guard let cached else { throw ReleaseLookupError.malformedResponse }
            return ReleaseLookup(release: cached.release, source: .cache)

        case 403, 429:
            // Out of allowance. A slightly stale version label beats an error
            // the user can do nothing about.
            guard let cached else { throw ReleaseLookupError.rateLimited }
            return ReleaseLookup(release: cached.release, source: .cache)

        default:
            throw ReleaseLookupError.unexpectedStatus(response.status)
        }
    }

    // MARK: - Parsing

    private struct APIRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name, size
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private func parse(_ body: Data) throws -> HMCLRelease {
        guard let payload = try? JSONDecoder().decode(APIRelease.self, from: body) else {
            throw ReleaseLookupError.malformedResponse
        }
        // Tags ship as "v3.16.3"; the asset is named "HMCL-3.16.3.jar".
        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName
        let expected = "HMCL-\(version).jar"

        guard let asset = payload.assets.first(where: { $0.name == expected }) else {
            throw ReleaseLookupError.noJarAsset
        }
        return HMCLRelease(
            version: version,
            jarName: asset.name,
            jarURL: asset.browserDownloadURL,
            jarSize: asset.size
        )
    }

    // MARK: - Cache

    private struct Cache: Codable {
        let etag: String?
        let release: HMCLRelease
    }

    private func loadCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func saveCache(_ cache: Cache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }
}
