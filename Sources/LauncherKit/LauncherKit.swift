import Foundation

/// Identity of the app on disk. Everything the launcher downloads lives under a
/// directory named after this, so nothing it does can collide with a system Java.
public enum AppIdentity {
    public static let bundleIdentifier = "net.tlau.HMCLLauncher"
    public static let displayName = "HMCL Launcher"
    public static let version = "1.0.0"
}
