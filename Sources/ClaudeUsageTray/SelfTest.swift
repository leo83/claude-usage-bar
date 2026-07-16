import Foundation

/// A tiny headless check that the real API JSON decodes into three bars.
/// Sample body is the actual `limits` array captured from the live endpoint.
enum SelfTest {
    static let sample = """
    {"five_hour":{"utilization":58.0},"seven_day":{"utilization":56.0},
     "limits":[
       {"kind":"session","group":"session","percent":58,"severity":"normal","resets_at":"2026-07-15T15:19:59.730336+00:00","scope":null,"is_active":false},
       {"kind":"weekly_all","group":"weekly","percent":56,"severity":"normal","resets_at":"2026-07-20T13:59:59.730364+00:00","scope":null,"is_active":false},
       {"kind":"weekly_scoped","group":"weekly","percent":80,"severity":"warning","resets_at":"2026-07-20T13:59:59.730857+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}
     ]}
    """

    static func run() {
        guard let data = sample.data(using: .utf8) else {
            print("selftest: FAIL — sample encoding"); exit(1)
        }
        do {
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            let bars = UsageMapper.bars(from: decoded.limits)
            print("selftest: decoded \(bars.count) bars")
            precondition(bars.count == 3, "expected 3 bars")
            for bar in bars {
                let reset = bar.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "—"
                print("  \(bar.label): \(Int(bar.percent))%  severity=\(bar.severity)  reset=\(reset)")
            }
            precondition(bars[0].label.contains("Сессия"))
            precondition(bars[2].label.contains("Fable"), "scoped model name should surface")
            precondition(bars[0].letter == "s" && bars[1].letter == "w" && bars[2].letter == "f",
                         "letters s/w/f")
            precondition(bars[0].resetsAt != nil, "date parsing should succeed")
            precondition(!bars.contains { $0.isBlocking }, "sample has no blocking limit")

            // isBlocking rules.
            let blocked = BarSpec(label: "x", letter: "f", percent: 100, severity: "critical", resetsAt: nil)
            precondition(blocked.isBlocking, "percent 100 / critical must block")
            // critical is the top *warning* tier (~90%), NOT exhaustion — it
            // must not trigger the "лимит исчерпан" countdown.
            let critical90 = BarSpec(label: "x", letter: "f", percent: 90, severity: "critical", resetsAt: nil)
            precondition(!critical90.isBlocking, "critical at 90% must NOT block")
            let exceeded = BarSpec(label: "x", letter: "f", percent: 95, severity: "exceeded", resetsAt: nil)
            precondition(exceeded.isBlocking, "explicit exceeded severity must block")

            // Error classification: transient errors keep the last reading;
            // actionable ones must surface.
            precondition(UsageError.http(429).isTransient, "429 is transient")
            precondition(UsageError.http(503).isTransient, "5xx is transient")
            precondition(UsageError.network("x").isTransient, "network is transient")
            precondition(!UsageError.unauthorized.isTransient, "401 must stay prominent")
            precondition(!UsageError.noToken.isTransient, "no-token must stay prominent")
            precondition(UsageError.http(429).localizedDescription.contains("429"), "429 has a message")

            // Rendering smoke test — rasterize to run the draw handler (knockout
            // letters, sparkle, countdown text) in every mode without crashing.
            for mono in [true, false] {
                for icon in [true, false] {
                    for letters in [true, false] {
                        precondition(BarsRenderer.image(for: bars, monochrome: mono, showLetters: letters, showIcon: icon, countdown: nil)
                            .tiffRepresentation != nil, "bars render \(mono)/\(letters)/icon=\(icon)")
                    }
                    precondition(BarsRenderer.image(for: bars, monochrome: mono, showLetters: true, showIcon: icon, countdown: "1:23")
                        .tiffRepresentation != nil, "countdown render \(mono)/icon=\(icon)")
                    precondition(BarsRenderer.placeholder(monochrome: mono, showLetters: true, showIcon: icon)
                        .tiffRepresentation != nil, "placeholder render \(mono)/icon=\(icon)")
                }
            }
            print("selftest: render OK (bars + countdown + placeholder, mono & colored)")
            print("selftest: OK")
        } catch {
            print("selftest: FAIL — \(error)"); exit(1)
        }
    }

    /// Live end-to-end probe against the real endpoint (no GUI).
    static func probe() {
        // Raw settings as this process's UserDefaults sees them (no password leak).
        let rawURL = Settings.proxyURL
        let scheme = rawURL.contains("://") ? String(rawURL.prefix(while: { $0 != "/" })) : "(none)"
        let hostTail = rawURL.components(separatedBy: "@").last ?? ""
        print("probe: bundleID = \(Bundle.main.bundleIdentifier ?? "nil")")
        print("probe: proxyEnabled = \(Settings.proxyEnabled), proxyURL.len = \(rawURL.count), scheme = \(scheme), hostTail = \(hostTail)")

        Settings.adoptEnvProxyIfEmpty()
        let tok = Credentials.accessToken()
        print("probe: token present = \(tok != nil), length = \(tok?.count ?? -1)")
        if let proxy = Settings.activeProxy {
            let auth = (proxy.username != nil) ? " (auth: \(proxy.username!):***)" : ""
            print("probe: proxy = \(proxy.host):\(proxy.port)\(auth)")
        } else {
            print("probe: proxy = none")
        }
        var done = false
        // Completion is delivered on the main queue; pump the main run loop so
        // it can fire (there is no NSApplication run loop in probe mode).
        UsageClient().fetch { result in
            switch result {
            case .success(let limits):
                let bars = UsageMapper.bars(from: limits)
                print("probe: OK — \(bars.count) bars")
                for bar in bars {
                    print("  \(bar.label): \(Int(bar.percent.rounded()))% (\(bar.severity))")
                }
            case .failure(let error):
                print("probe: FAIL — \(error.localizedDescription)")
            }
            done = true
        }
        let deadline = Date().addingTimeInterval(30)
        while !done && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
        }
    }

    /// Repeats the app's exact single request N times (no retry) and reports the
    /// raw outcome mix — specifically how many hit CFNetwork 310 (HTTPS proxy
    /// CONNECT failure). This is the before/after gate for proxy-connection fixes.
    static func probeLoop(count: Int) {
        Settings.adoptEnvProxyIfEmpty()
        if let proxy = Settings.activeProxy {
            print("probe-loop: proxy = \(proxy.host):\(proxy.port) auth=\(proxy.username != nil)")
        } else {
            print("probe-loop: proxy = none")
        }
        let client = UsageClient()
        var conn = 0, e310 = 0, otherNet = 0
        for i in 1...count {
            var done = false
            client.fetchOnce { result in
                switch result {
                case .success:
                    conn += 1; print("  #\(i): OK (connected)")
                case .failure(let err):
                    if case .network(let msg) = err {
                        if msg.contains("310") { e310 += 1; print("  #\(i): 310 proxy CONNECT fail") }
                        else { otherNet += 1; print("  #\(i): net — \(msg)") }
                    } else {
                        conn += 1; print("  #\(i): connected (HTTP: \(err.localizedDescription))")
                    }
                }
                done = true
            }
            let deadline = Date().addingTimeInterval(25)
            while !done && Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(1.0))   // spacing
        }
        print("probe-loop: connected=\(conn) e310=\(e310) otherNet=\(otherNet) of \(count)")
    }
}
