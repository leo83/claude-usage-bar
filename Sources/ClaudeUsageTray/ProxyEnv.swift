import Foundation

/// Reads an HTTP(S) proxy URL from the environment.
///
/// Apps launched from Finder/Spotlight do NOT inherit the shell environment, so
/// we first check our own process env (fast path when launched from a terminal),
/// then fall back to querying the user's login shell — which sources their
/// profile (`.zshrc`/`.zprofile`/`.bash_profile`) where the proxy is exported.
/// This makes "Взять из env" work regardless of how the app was launched.
enum ProxyEnv {
    /// Preferred order: HTTPS first (our endpoint is https), then HTTP, then ALL.
    private static let keys = [
        "HTTPS_PROXY", "https_proxy",
        "HTTP_PROXY", "http_proxy",
        "ALL_PROXY", "all_proxy",
    ]

    /// The first non-empty proxy URL found, e.g. `http://user:pass@host:3128`.
    static func current() -> String? {
        if let value = fromProcessEnv() { return value }
        return fromLoginShell()
    }

    private static func fromProcessEnv() -> String? {
        let env = ProcessInfo.processInfo.environment
        for key in keys {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Asks the user's login+interactive shell to print the first set proxy var.
    private static func fromLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // `${VAR:-…}` chain returns the first non-empty of the candidates.
        let expr = "printf %s \"${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-${ALL_PROXY:-${all_proxy:-}}}}}}\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", expr]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()      // swallow rc noise
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}

/// Parsed components of a proxy URL, ready for URLSession configuration.
struct ProxyConfig {
    let host: String
    let port: Int
    let username: String?
    let password: String?

    /// Parses `scheme://[user:pass@]host:port`. Scheme is optional.
    init?(urlString: String) {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }   // tolerate host:port only
        guard let comps = URLComponents(string: s),
              let host = comps.host, !host.isEmpty else { return nil }
        self.host = host
        self.port = comps.port ?? 3128
        self.username = (comps.user?.isEmpty == false) ? comps.user : nil
        // URLComponents percent-decodes user/password automatically.
        self.password = (comps.password?.isEmpty == false) ? comps.password : nil
    }
}
