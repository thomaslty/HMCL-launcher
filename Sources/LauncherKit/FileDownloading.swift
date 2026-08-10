import Foundation

/// Seam for tests, and the reason a 126 MB runtime download can be exercised
/// without touching the network.
public protocol FileDownloading: Sendable {
    func download(
        from url: URL,
        to destination: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws
}

public struct URLSessionDownloader: FileDownloading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        from url: URL,
        to destination: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let delegate = ProgressDelegate(onProgress: onProgress)
        let (temporary, response) = try await session.download(from: url, delegate: delegate)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RuntimeInstallError.unexpectedStatus(http.statusCode)
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        onProgress(1)
    }
}

/// URLSession reports download progress through a delegate; the async
/// `download(from:)` call on its own gives no way to observe it.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The async download(from:) API takes the file from here.
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
