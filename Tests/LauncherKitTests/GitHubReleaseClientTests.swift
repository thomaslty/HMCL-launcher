import Foundation
import Testing

@testable import LauncherKit

/// Serves canned responses in order and remembers what was asked for.
actor StubFetcher: HTTPFetching {
    private var queued: [HTTPResponse]
    private(set) var requestedHeaders: [[String: String]] = []
    private(set) var requestedURLs: [URL] = []

    init(_ queued: [HTTPResponse]) {
        self.queued = queued
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requestedURLs.append(url)
        requestedHeaders.append(headers)
        guard !queued.isEmpty else {
            throw StubError.ranOut
        }
        return queued.removeFirst()
    }

    enum StubError: Error { case ranOut }
}

private func releaseJSON(tag: String, assets: [String]) -> Data {
    let assetJSON = assets.map { name in
        """
        {"name":"\(name)","size":10319057,
         "browser_download_url":"https://github.com/HMCL-dev/HMCL/releases/download/\(tag)/\(name)"}
        """
    }.joined(separator: ",")
    return Data("""
    {"tag_name":"\(tag)","name":"\(tag)","prerelease":false,"assets":[\(assetJSON)]}
    """.utf8)
}

private func makeCacheURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "hmcl-cache-\(UUID().uuidString).json")
}

@Suite struct GitHubReleaseClientTests {
    @Test func parsesVersionAndJarAssetFromLatestRelease() async throws {
        let cache = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cache) }
        let fetcher = StubFetcher([
            HTTPResponse(
                status: 200,
                body: releaseJSON(tag: "v3.16.3", assets: ["HMCL-3.16.3.deb", "HMCL-3.16.3.jar"]),
                headers: ["Etag": "W/\"abc123\""]
            )
        ])
        let client = GitHubReleaseClient(fetcher: fetcher, cacheURL: cache)

        let lookup = try await client.latestRelease()

        #expect(lookup.release.version == "3.16.3")
        #expect(lookup.release.jarName == "HMCL-3.16.3.jar")
        #expect(lookup.source == .network)
    }

    @Test func releaseWithoutJarAssetFails() async throws {
        let cache = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cache) }
        let fetcher = StubFetcher([
            HTTPResponse(status: 200, body: releaseJSON(tag: "v3.16.3", assets: ["HMCL-3.16.3.exe"]), headers: [:])
        ])
        let client = GitHubReleaseClient(fetcher: fetcher, cacheURL: cache)

        await #expect(throws: ReleaseLookupError.noJarAsset) {
            try await client.latestRelease()
        }
        #expect(!FileManager.default.fileExists(atPath: cache.path), "nothing partial should be cached")
    }

    @Test func storesEtagAndSendsItOnTheNextRequest() async throws {
        let cache = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cache) }
        let fetcher = StubFetcher([
            HTTPResponse(
                status: 200,
                body: releaseJSON(tag: "v3.16.3", assets: ["HMCL-3.16.3.jar"]),
                headers: ["ETag": "W/\"abc123\""]
            ),
            HTTPResponse(status: 304, body: Data(), headers: [:]),
        ])
        let client = GitHubReleaseClient(fetcher: fetcher, cacheURL: cache)

        _ = try await client.latestRelease()
        let second = try await client.latestRelease()

        #expect(second.release.version == "3.16.3")
        #expect(second.source == .cache)
        let headers = await fetcher.requestedHeaders
        #expect(headers.count == 2)
        #expect(headers[0]["If-None-Match"] == nil)
        #expect(headers[1]["If-None-Match"] == "W/\"abc123\"")
    }

    @Test func rateLimitFallsBackToTheCache() async throws {
        let cache = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cache) }
        let fetcher = StubFetcher([
            HTTPResponse(
                status: 200,
                body: releaseJSON(tag: "v3.16.3", assets: ["HMCL-3.16.3.jar"]),
                headers: ["ETag": "W/\"abc123\""]
            ),
            HTTPResponse(status: 403, body: Data(), headers: ["x-ratelimit-remaining": "0"]),
        ])
        let client = GitHubReleaseClient(fetcher: fetcher, cacheURL: cache)

        _ = try await client.latestRelease()
        let second = try await client.latestRelease()

        #expect(second.release.version == "3.16.3")
        #expect(second.source == .cache)
    }

    @Test func rateLimitWithoutACacheFails() async throws {
        let cache = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cache) }
        let fetcher = StubFetcher([
            HTTPResponse(status: 403, body: Data(), headers: ["x-ratelimit-remaining": "0"])
        ])
        let client = GitHubReleaseClient(fetcher: fetcher, cacheURL: cache)

        await #expect(throws: ReleaseLookupError.rateLimited) {
            try await client.latestRelease()
        }
    }

    @Test func tagWithoutALeadingVIsAccepted() async throws {
        let cache = makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cache) }
        let fetcher = StubFetcher([
            HTTPResponse(status: 200, body: releaseJSON(tag: "3.16.3", assets: ["HMCL-3.16.3.jar"]), headers: [:])
        ])
        let client = GitHubReleaseClient(fetcher: fetcher, cacheURL: cache)

        let lookup = try await client.latestRelease()

        #expect(lookup.release.version == "3.16.3")
    }
}
