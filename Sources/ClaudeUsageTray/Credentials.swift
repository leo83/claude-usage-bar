import Foundation

/// Reads the Claude Code OAuth access token.
///
/// Two sources are tried, for portability across Claude Code setups:
/// 1. The file `~/.claude/.credentials.json` (JSON with `claudeAiOauth.accessToken`).
/// 2. The macOS login Keychain generic-password item `Claude Code-credentials`,
///    read by shelling out to `/usr/bin/security` on purpose: the Keychain
///    access prompt is then bound to Apple's stable, signed `security` binary,
///    so a one-time "Always Allow" survives rebuilds of this (ad-hoc) app.
///
/// Either source may hold a bare token or a JSON blob; both are handled.
enum Credentials {
    static let keychainService = "Claude Code-credentials"

    static func accessToken() -> String? {
        tokenFromFile() ?? tokenFromKeychain()
    }

    // MARK: - File

    private static func tokenFromFile() -> String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/.credentials.json")
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return token(fromJSON: data)
    }

    // MARK: - Keychain

    private static func tokenFromKeychain() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return nil }

        if raw.hasPrefix("{"), let jsonData = raw.data(using: .utf8),
           let token = token(fromJSON: jsonData) {
            return token
        }
        return raw
    }

    // MARK: - Shared parsing

    /// Extracts `claudeAiOauth.accessToken` (or a top-level `accessToken`).
    private static func token(fromJSON data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let oauth = obj["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        if let token = obj["accessToken"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }
}
