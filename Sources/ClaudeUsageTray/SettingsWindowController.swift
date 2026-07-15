import AppKit

/// A small settings window: proxy on/off + full proxy URL, and poll interval.
final class SettingsWindowController: NSWindowController {
    private let proxyCheckbox = NSButton(checkboxWithTitle: "Использовать HTTP(S)-прокси", target: nil, action: nil)
    private let colorCheckbox = NSButton(checkboxWithTitle: "Цветные столбики (иначе чёрно-белые)", target: nil, action: nil)
    private let lettersCheckbox = NSButton(checkboxWithTitle: "Показывать буквы в столбиках (s / w / f)", target: nil, action: nil)
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

        let hint = NSTextField(wrappingLabelWithString:
            "Формат как в HTTPS_PROXY, включая логин:пароль. Пусто = без прокси. " +
            "Если поле пустое, прокси автоматически берётся из окружения (login-shell).")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: "Сохранить", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Закрыть", target: self, action: #selector(closeWindow))

        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, proxyCheckbox],
            [proxyLabel, proxyField],
            [intervalLabel, intervalField],
            [NSGridCell.emptyContentView, colorCheckbox],
            [NSGridCell.emptyContentView, lettersCheckbox],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing   // labels right-aligned
        grid.column(at: 1).xPlacement = .fill        // fields stretch → aligned edges
        // Checkboxes: keep them left-aligned (not stretched) in the input column.
        for row in [0, 3, 4] {
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

    private func loadValues() {
        proxyCheckbox.state = Settings.proxyEnabled ? .on : .off
        colorCheckbox.state = Settings.monochrome ? .off : .on
        lettersCheckbox.state = Settings.showLetters ? .on : .off
        proxyField.stringValue = Settings.proxyURL
        intervalField.stringValue = String(Settings.pollSeconds)
        updateProxyFieldsEnabled()
    }

    private func updateProxyFieldsEnabled() {
        proxyField.isEnabled = proxyCheckbox.state == .on
    }

    @objc private func proxyToggled() {
        updateProxyFieldsEnabled()
    }

    @objc private func save() {
        Settings.proxyEnabled = proxyCheckbox.state == .on
        Settings.monochrome = colorCheckbox.state == .off
        Settings.showLetters = lettersCheckbox.state == .on
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
