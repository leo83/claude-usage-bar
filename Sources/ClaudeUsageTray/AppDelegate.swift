import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let client = UsageClient()
    private var timer: Timer?
    private var minuteTimer: Timer?
    private var lastBars: [BarSpec] = []
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.adoptEnvProxyIfEmpty()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BarsRenderer.placeholder(monochrome: Settings.monochrome, showLetters: Settings.showLetters)
        statusItem.button?.toolTip = "Claude usage — загрузка…"

        buildMenu(bars: [], error: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .settingsChanged, object: nil
        )

        refresh()
        startTimer()

        // Ticks the blocking countdown once a minute, independent of polling.
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, !self.lastBars.isEmpty else { return }
            self.renderIcon(bars: self.lastBars)
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
                self.renderIcon(bars: bars)
                self.buildMenu(bars: bars, error: nil)
            case .failure(let error):
                self.lastBars = []
                self.statusItem.button?.image = BarsRenderer.placeholder(monochrome: Settings.monochrome, showLetters: Settings.showLetters)
                self.statusItem.button?.toolTip = "Claude usage — \(error.localizedDescription)"
                self.buildMenu(bars: [], error: error)
            }
        }
    }

    /// Sets the status-item image + tooltip from bars, showing a blocking
    /// countdown instead of the bars when a limit fully blocks work.
    private func renderIcon(bars: [BarSpec]) {
        let blockingReset = soonestBlockingReset(bars)
        let countdown = blockingReset.map { compactCountdown(to: $0) }
        statusItem.button?.image = BarsRenderer.image(for: bars, monochrome: Settings.monochrome, showLetters: Settings.showLetters, countdown: countdown)
        statusItem.button?.toolTip = tooltip(for: bars, blockingReset: blockingReset)
    }

    // MARK: - Countdown helpers

    /// Soonest future reset among fully-blocking limits, if any.
    private func soonestBlockingReset(_ bars: [BarSpec]) -> Date? {
        bars.filter { $0.isBlocking }
            .compactMap { $0.resetsAt }
            .filter { $0.timeIntervalSinceNow > 0 }
            .min()
    }

    /// Compact `H:MM` for the icon.
    private func compactCountdown(to date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSinceNow))
        return String(format: "%d:%02d", secs / 3600, (secs % 3600) / 60)
    }

    /// Human `Xч Yм` for tooltip / menu.
    private func humanCountdown(to date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSinceNow))
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)ч \(m)м" : "\(m)м"
    }

    // MARK: - Tooltip (hover)

    private func tooltip(for bars: [BarSpec], blockingReset: Date?) -> String {
        var lines = ["Claude usage"]
        if let reset = blockingReset {
            lines.append("⛔ Лимит исчерпан · разблокировка через \(humanCountdown(to: reset))")
        }
        for bar in bars {
            let pct = Int(bar.percent.rounded())
            var line = "• \(bar.label): \(pct)%"
            if bar.isBlocking { line += " ⛔" }
            if let reset = bar.resetsAt {
                line += "  · сброс \(Self.resetFormatter.string(from: reset))"
            }
            lines.append(line)
        }
        if bars.isEmpty { lines.append("нет данных") }
        return lines.joined(separator: "\n")
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return f
    }()

    // MARK: - Menu

    private func buildMenu(bars: [BarSpec], error: UsageError?) {
        let menu = NSMenu()

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
                    title += "  ·  сброс \(Self.resetFormatter.string(from: reset))"
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
