import Foundation

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data
    /// Lower-cased keys, because HTTP header names are case insensitive and
    /// GitHub has shipped both `ETag` and `Etag` over the years.
    public let headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String]) {
        self.status = status
        self.body = body
        self.headers = headers.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// Seam for tests. Everything that talks to the network goes through this so the
/// release, runtime and jar flows can be exercised without a socket.
public protocol HTTPFetching: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public struct URLSessionFetcher: HTTPFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        // We do our own conditional requests. Left on the default policy,
        // URLSession answers a 304 from its own cache and hands back a 200,
        // which hides the status we are branching on.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let pairs = (http?.allHeaderFields ?? [:]).compactMap { key, value -> (String, String)? in
            guard let key = key as? String, let value = value as? String else { return nil }
            return (key, value)
        }
        return HTTPResponse(
            status: http?.statusCode ?? 0,
            body: data,
            headers: Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        )
    }
}
