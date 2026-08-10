import CryptoKit
import Foundation

public enum Checksum {
    /// Streams the file in 1 MiB chunks — a Liberica JRE is ~126 MB and does not
    /// belong in memory just to be hashed.
    ///
    /// SHA-1 because that is the only checksum BellSoft publishes.
    public static func sha1(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = Insecure.SHA1()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum VersionOrder {
    /// Splits "25.0.4+9" into [25, 0, 4, 9] so versions sort numerically rather
    /// than as strings, where "9" would beat "11".
    public static func numbers(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    public static func newestFirst(_ lhs: String, _ rhs: String) -> Bool {
        numbers(rhs).lexicographicallyPrecedes(numbers(lhs))
    }
}
