import AppKit

// Headless smoke test: decode a real captured response and print the bars.
// Usage: ClaudeUsageTray --selftest
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

// Headless live probe: real Keychain read + HTTPS fetch + decode, then exit.
if CommandLine.arguments.contains("--probe") {
    SelfTest.probe()
    exit(0)
}

// Diagnostic: repeat the exact request N times, report the raw 310 rate.
// Usage: ClaudeUsageTray --probe-loop [N]
if let idx = CommandLine.arguments.firstIndex(of: "--probe-loop") {
    let n = (idx + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[idx + 1]) : nil) ?? 20
    SelfTest.probeLoop(count: n)
    exit(0)
}

// Menu-bar-only agent app: no Dock icon, no main menu bar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
