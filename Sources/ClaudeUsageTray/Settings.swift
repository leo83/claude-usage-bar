import Foundation

/// Persistent user settings backed by UserDefaults.
///
/// The proxy is stored as a full URL string (e.g. `http://user:pass@host:3128`)
/// to mirror the `HTTPS_PROXY`/`HTTP_PROXY` environment format 1:1, including
/// optional credentials. NOTE: this string (with any password) lives in
/// UserDefaults in plaintext — acceptable for a personal tool, same as the
/// shell environment it comes from.
enum Settings {
    private static let d = UserDefaults.standard

    private enum Key {
        static let proxyEnabled = "proxyEnabled"
        static let proxyURL = "proxyURL"
        static let pollSeconds = "pollSeconds"
        static let monochrome = "monochrome"
        static let showLetters = "showLetters"
        static let showIcon = "showIcon"
        static let displayTimeZone = "displayTimeZone"
    }

    /// Icon style: monochrome template (default) vs colored severity bars.
    static var monochrome: Bool {
        get { d.object(forKey: Key.monochrome) == nil ? true : d.bool(forKey: Key.monochrome) }
        set { d.set(newValue, forKey: Key.monochrome) }
    }

    /// Show the s / w / f letters inside the bars (default true).
    static var showLetters: Bool {
        get { d.object(forKey: Key.showLetters) == nil ? true : d.bool(forKey: Key.showLetters) }
        set { d.set(newValue, forKey: Key.showLetters) }
    }

    /// Show the Claude sparkle mark before the bars (default true).
    static var showIcon: Bool {
        get { d.object(forKey: Key.showIcon) == nil ? true : d.bool(forKey: Key.showIcon) }
        set { d.set(newValue, forKey: Key.showIcon) }
    }

    /// TZ identifier for displaying reset times; empty = system local zone.
    static var displayTimeZoneID: String {
        get { d.string(forKey: Key.displayTimeZone) ?? "" }
        set { d.set(newValue, forKey: Key.displayTimeZone) }
    }

    /// Effective zone for reset display: the chosen one, else the live local zone.
    static var displayTimeZone: TimeZone {
        if !displayTimeZoneID.isEmpty, let tz = TimeZone(identifier: displayTimeZoneID) {
            return tz
        }
        return .autoupdatingCurrent
    }

    static var proxyEnabled: Bool {
        get { d.bool(forKey: Key.proxyEnabled) }
        set { d.set(newValue, forKey: Key.proxyEnabled) }
    }

    /// Full proxy URL, e.g. `http://user:pass@host:3128`. Empty = none.
    static var proxyURL: String {
        get { d.string(forKey: Key.proxyURL) ?? "" }
        set { d.set(newValue, forKey: Key.proxyURL) }
    }

    /// Poll interval in seconds. Defaults to 60, clamped to a sane minimum.
    static var pollSeconds: Int {
        get {
            let v = d.integer(forKey: Key.pollSeconds)
            return v <= 0 ? 60 : max(15, v)
        }
        set { d.set(max(15, newValue), forKey: Key.pollSeconds) }
    }

    /// Adopt the environment proxy whenever no valid proxy URL is configured.
    /// Runs on each launch; a valid saved proxy is always kept. This makes the
    /// corporate proxy "just work" without any manual step.
    static func adoptEnvProxyIfEmpty() {
        guard ProxyConfig(urlString: proxyURL) == nil else { return }
        if let envProxy = ProxyEnv.current() {
            proxyURL = envProxy
            proxyEnabled = true
        }
    }

    /// Parsed proxy config, or nil when disabled/empty/unparseable.
    static var activeProxy: ProxyConfig? {
        guard proxyEnabled, !proxyURL.isEmpty else { return nil }
        return ProxyConfig(urlString: proxyURL)
    }
}
