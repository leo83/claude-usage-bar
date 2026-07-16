import AppKit

/// Build identity. The short git hash is injected into Info.plist at bundle
/// time (`scripts/bundle.sh`); plain `swift build` debug runs have no bundle
/// Info.plist, so they report "dev".
enum BuildInfo {
    static var gitHash: String {
        guard let h = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String,
              !h.isEmpty else { return "dev" }
        return h
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }

    /// e.g. "v0.1.0 (c6aa636)".
    static var display: String { "v\(version) (\(gitHash))" }

    /// Copy the hash to the system pasteboard.
    static func copyHashToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(gitHash, forType: .string)
    }
}
