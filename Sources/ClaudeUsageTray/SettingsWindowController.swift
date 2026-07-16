import AppKit

/// A small settings window: proxy on/off + full proxy URL, and poll interval.
final class SettingsWindowController: NSWindowController {
    private let proxyCheckbox = NSButton(checkboxWithTitle: "Использовать HTTP(S)-прокси", target: nil, action: nil)
    private let colorCheckbox = NSButton(checkboxWithTitle: "Цветные столбики (иначе чёрно-белые)", target: nil, action: nil)
    private let lettersCheckbox = NSButton(checkboxWithTitle: "Показывать буквы в столбиках (s / w / f)", target: nil, action: nil)
    private let iconCheckbox = NSButton(checkboxWithTitle: "Показывать значок Claude", target: nil, action: nil)
    private let copyBuildButton = NSButton(title: "Копировать", target: nil, action: nil)
    private let proxyField = NSTextField()
    private let intervalField = NSTextField()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Настройки"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        buildUI()
        loadValues()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        proxyCheckbox.target = self
        proxyCheckbox.action = #selector(proxyToggled)

        let proxyLabel = makeLabel("Прокси URL:")
        let intervalLabel = makeLabel("Интервал (сек):")

        proxyField.placeholderString = "http://user:pass@host:3128"
        intervalField.placeholderString = "60"
        [proxyField, intervalField].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        // Robust single-line display for a long URL: scroll, don't wrap/clip to
        // one glyph run. (Fixes the field rendering only the "http://" scheme.)
        proxyField.usesSingleLineMode = true
        proxyField.lineBreakMode = .byTruncatingTail
        proxyField.cell?.wraps = false
        proxyField.cell?.isScrollable = true
        proxyField.maximumNumberOfLines = 1

        let hint = NSTextField(wrappingLabelWithString:
            "Формат как в HTTPS_PROXY, включая логин:пароль. Пусто = без прокси. " +
            "Если поле пустое, прокси автоматически берётся из окружения (login-shell).")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: "Сохранить", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Закрыть", target: self, action: #selector(closeWindow))

        // Build stamp: selectable hash + copy button.
        let buildLabel = makeLabel("Сборка:")
        let buildValue = NSTextField(labelWithString: BuildInfo.display)
        buildValue.isSelectable = true
        buildValue.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        buildValue.textColor = .secondaryLabelColor
        copyBuildButton.target = self
        copyBuildButton.action = #selector(copyBuild)
        copyBuildButton.controlSize = .small
        copyBuildButton.bezelStyle = .rounded
        let buildRow = NSStackView(views: [buildValue, copyBuildButton])
        buildRow.orientation = .horizontal
        buildRow.spacing = 8

        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, proxyCheckbox],
            [proxyLabel, proxyField],
            [intervalLabel, intervalField],
            [NSGridCell.emptyContentView, iconCheckbox],
            [NSGridCell.emptyContentView, colorCheckbox],
            [NSGridCell.emptyContentView, lettersCheckbox],
            [buildLabel, buildRow],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing   // labels right-aligned
        grid.column(at: 1).xPlacement = .fill        // fields stretch → aligned edges
        // Checkboxes + build row: keep left-aligned (not stretched) in the input column.
        for row in [0, 3, 4, 6] {
            grid.cell(atColumnIndex: 1, rowIndex: row).xPlacement = .leading
        }

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        content.addSubview(hint)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),

            proxyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),

            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    /// Re-reads persisted settings into the fields. Called on every open so the
    /// window always reflects the current stored state (e.g. an env-seeded proxy),
    /// not a snapshot taken at controller-init time.
    func loadValues() {
        proxyCheckbox.state = Settings.proxyEnabled ? .on : .off
        colorCheckbox.state = Settings.monochrome ? .off : .on
        lettersCheckbox.state = Settings.showLetters ? .on : .off
        iconCheckbox.state = Settings.showIcon ? .on : .off
        proxyField.stringValue = Settings.proxyURL
        intervalField.stringValue = String(Settings.pollSeconds)
        updateProxyFieldsEnabled()

        // Don't leave the (long) proxy value fully selected & scrolled under the
        // field editor — that renders as a truncated "http://". Show it from the
        // start with no selection, and keep initial focus off the text fields.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Disable smart-link/data detection on the shared field editor — a
            // URL with "://" can otherwise be reinterpreted while displayed.
            if let editor = self.window?.fieldEditor(true, for: self.proxyField) as? NSTextView {
                editor.isAutomaticLinkDetectionEnabled = false
                editor.isAutomaticDataDetectionEnabled = false
                editor.isAutomaticTextReplacementEnabled = false
            }
            self.window?.makeFirstResponder(nil)
            self.proxyField.needsDisplay = true
        }
    }

    private func updateProxyFieldsEnabled() {
        proxyField.isEnabled = proxyCheckbox.state == .on
    }

    @objc private func copyBuild() {
        BuildInfo.copyHashToPasteboard()
        copyBuildButton.title = "Скопировано ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyBuildButton.title = "Копировать"
        }
    }

    @objc private func proxyToggled() {
        updateProxyFieldsEnabled()
    }

    @objc private func save() {
        Settings.proxyEnabled = proxyCheckbox.state == .on
        Settings.monochrome = colorCheckbox.state == .off
        Settings.showLetters = lettersCheckbox.state == .on
        Settings.showIcon = iconCheckbox.state == .on
        Settings.proxyURL = proxyField.stringValue.trimmingCharacters(in: .whitespaces)
        if let interval = Int(intervalField.stringValue.trimmingCharacters(in: .whitespaces)) {
            Settings.pollSeconds = interval
        }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        closeWindow()
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
