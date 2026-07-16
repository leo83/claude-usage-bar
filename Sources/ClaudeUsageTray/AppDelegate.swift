import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let client = UsageClient()
    private var timer: Timer?
    private var minuteTimer: Timer?
    private var lastBars: [BarSpec] = []
    private var lastFetch: Date?
    private var currentStale: Stale?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.adoptEnvProxyIfEmpty()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BarsRenderer.placeholder(monochrome: Settings.monochrome, showLetters: Settings.showLetters, showIcon: Settings.showIcon)
        statusItem.button?.toolTip = "Claude usage — загрузка…"

        buildMenu(bars: [], error: nil, stale: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .settingsChanged, object: nil
        )

        refresh()
        startTimer()

        // Ticks the blocking countdown once a minute, independent of polling.
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, !self.lastBars.isEmpty else { return }
            self.renderIcon(bars: self.lastBars, stale: self.currentStale)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(Settings.pollSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func settingsChanged() {
        startTimer()   // interval may have changed
        refresh()      // proxy may have changed — re-fetch now
    }

    // MARK: - Fetch + render

    @objc func refresh() {
        client.fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let limits):
                let bars = UsageMapper.bars(from: limits)
                self.lastBars = bars
                self.lastFetch = Date()
                self.currentStale = nil
                self.renderIcon(bars: bars, stale: nil)
                self.buildMenu(bars: bars, error: nil, stale: nil)
            case .failure(let error):
                // Transient errors keep the last good reading visible (marked
                // stale) instead of blanking perfectly recent data.
                if error.isTransient, !self.lastBars.isEmpty {
                    let stale: Stale = (error: error, since: self.lastFetch)
                    self.currentStale = stale
                    self.renderIcon(bars: self.lastBars, stale: stale)
                    self.buildMenu(bars: self.lastBars, error: nil, stale: stale)
                } else {
                    self.lastBars = []
                    self.currentStale = nil
                    self.statusItem.button?.image = BarsRenderer.placeholder(monochrome: Settings.monochrome, showLetters: Settings.showLetters, showIcon: Settings.showIcon)
                    self.statusItem.button?.toolTip = "Claude usage — \(error.localizedDescription)"
                    self.buildMenu(bars: [], error: error, stale: nil)
                }
            }
        }
    }

    /// A last-good reading kept on screen after a transient fetch failure.
    typealias Stale = (error: UsageError, since: Date?)

    /// Sets the status-item image + tooltip from bars, showing a blocking
    /// countdown instead of the bars when a limit fully blocks work.
    private func renderIcon(bars: [BarSpec], stale: Stale?) {
        let blockingReset = soonestBlockingReset(bars)
        let countdown = blockingReset.map { compactCountdown(to: $0) }
        statusItem.button?.image = BarsRenderer.image(for: bars, monochrome: Settings.monochrome, showLetters: Settings.showLetters, showIcon: Settings.showIcon, countdown: countdown)
        statusItem.button?.toolTip = tooltip(for: bars, blockingReset: blockingReset, stale: stale)
    }

    // MARK: - Countdown helpers

    /// Soonest future reset among fully-blocking limits, if any.
    private func soonestBlockingReset(_ bars: [BarSpec]) -> Date? {
        bars.filter { $0.isBlocking }
            .compactMap { $0.resetsAt }
            .filter { $0.timeIntervalSinceNow > 0 }
            .min()
    }

    /// Compact `H:MM` for the icon. Rounds minutes UP so an active lockout never
    /// reads `0:00` while time still remains — the last minute shows `0:01`.
    private func compactCountdown(to date: Date) -> String {
        let totalMin = ceilMinutes(to: date)
        return String(format: "%d:%02d", totalMin / 60, totalMin % 60)
    }

    /// Human `Xч Yм` for tooltip / menu (minutes rounded up, see compactCountdown).
    private func humanCountdown(to date: Date) -> String {
        let totalMin = ceilMinutes(to: date)
        let h = totalMin / 60, m = totalMin % 60
        return h > 0 ? "\(h)ч \(m)м" : "\(m)м"
    }

    /// Whole minutes remaining, rounded up (0 only once the instant has passed).
    private func ceilMinutes(to date: Date) -> Int {
        let secs = max(0, Int(date.timeIntervalSinceNow.rounded(.up)))
        return (secs + 59) / 60
    }

    /// "данные от 18:42 · Слишком много запросов (429)" — one line explaining
    /// that the bars are the last successful reading, not live.
    private func staleNote(_ stale: Stale) -> String {
        let when = stale.since.map { "данные от \(formatClock($0))" } ?? "нет свежих данных"
        return "\(when) · \(stale.error.localizedDescription)"
    }

    /// Reset date/time in the user-chosen (or system) zone — see Settings.displayTimeZone.
    private func formatReset(_ date: Date) -> String {
        Self.resetFormatter.timeZone = Settings.displayTimeZone
        return Self.resetFormatter.string(from: date)
    }

    private func formatClock(_ date: Date) -> String {
        Self.timeFormatter.timeZone = Settings.displayTimeZone
        return Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        // autoupdatingCurrent: reflect the live system zone. A plain `static`
        // formatter snapshots the zone at first use; when the app is launched
        // as a login item before the TZ is resolved, that snapshot is GMT and
        // reset times would show in UTC for the whole session.
        f.timeZone = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return f
    }()

    // MARK: - Tooltip (hover)

    private func tooltip(for bars: [BarSpec], blockingReset: Date?, stale: Stale?) -> String {
        var lines = ["Claude usage"]
        if let stale = stale {
            lines.append("⚠️ \(staleNote(stale))")
        }
        if let reset = blockingReset {
            lines.append("⛔ Лимит исчерпан · разблокировка через \(humanCountdown(to: reset))")
        }
        for bar in bars {
            let pct = Int(bar.percent.rounded())
            var line = "• \(bar.label): \(pct)%"
            if bar.isBlocking { line += " ⛔" }
            if let reset = bar.resetsAt {
                line += "  · сброс \(formatReset(reset))"
            }
            lines.append(line)
        }
        if bars.isEmpty { lines.append("нет данных") }
        return lines.joined(separator: "\n")
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .autoupdatingCurrent   // live local zone, not a frozen snapshot
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return f
    }()

    // MARK: - Menu

    private func buildMenu(bars: [BarSpec], error: UsageError?, stale: Stale?) {
        let menu = NSMenu()

        if let stale = stale {
            let item = NSMenuItem(title: "⚠️ \(staleNote(stale))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        if let error = error {
            let item = NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if bars.isEmpty {
            let item = NSMenuItem(title: "Загрузка…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for bar in bars {
                let pct = Int(bar.percent.rounded())
                var title = "\(bar.label) — \(pct)%"
                if bar.isBlocking, let reset = bar.resetsAt {
                    title += "  ·  ⛔ разблокировка через \(humanCountdown(to: reset))"
                } else if let reset = bar.resetsAt {
                    title += "  ·  сброс \(formatReset(reset))"
                }
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        menu.addItem(withTitle: "Обновить", action: #selector(refresh), keyEquivalent: "r")
            .target = self
        menu.addItem(withTitle: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self

        let loginItem = NSMenuItem(
            title: "Запускать при входе",
            action: #selector(toggleLoginItem), keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Выход", action: #selector(quit), keyEquivalent: "q")
            .target = self

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.loadValues()
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login (macOS 13+)

    private func isLoginItemEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLoginItem() {
        do {
            if isLoginItemEnabled() {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось изменить автозапуск"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        // Rebuild so the checkmark reflects the new state.
        refresh()
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("ClaudeUsageTray.settingsChanged")
}
