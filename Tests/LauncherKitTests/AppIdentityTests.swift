import Testing

@testable import LauncherKit

@Test func bundleIdentifierIsStable() {
    // The workspace directory is named after this, so changing it strands
    // everything a user already downloaded.
    #expect(AppIdentity.bundleIdentifier == "net.tlau.HMCLLauncher")
}
