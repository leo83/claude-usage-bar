.PHONY: build run app install launch login unlogin uninstall clean selftest probe

APP := /Applications/ClaudeUsageTray.app

# Debug build
build:
	swift build

# Run the debug binary directly (menu-bar icon appears; Ctrl-C to stop).
# Run from a terminal that has HTTPS_PROXY exported so env-seeding works.
run: build
	./.build/debug/ClaudeUsageTray

# Headless checks
selftest: build
	./.build/debug/ClaudeUsageTray --selftest

probe: build
	./.build/debug/ClaudeUsageTray --probe

# Build the release .app bundle (ad-hoc signed)
app:
	bash scripts/bundle.sh

# Build the bundle and copy it to /Applications.
# Kill any running instance first — `open -a` only *activates* an already-running
# accessory app, so without this the old binary keeps running after reinstall.
install: app
	-killall ClaudeUsageTray 2>/dev/null || true
	rm -rf /Applications/ClaudeUsageTray.app
	cp -R .build/ClaudeUsageTray.app /Applications/
	@echo "Установлено: /Applications/ClaudeUsageTray.app  (open -a ClaudeUsageTray)"

launch:
	open -a ClaudeUsageTray

# Автозапуск при входе через переносимый per-user LaunchAgent.
# plist генерируется из bundle id/пути установленного .app — ничего
# машинно-специфичного не коммитится.
login: install
	bash scripts/loginitem.sh on "$(APP)"
	open -a ClaudeUsageTray

unlogin:
	-bash scripts/loginitem.sh off "$(APP)" 2>/dev/null || true

# Полное удаление: снять автозапуск и убрать .app из /Applications.
uninstall:
	-bash scripts/loginitem.sh off "$(APP)" 2>/dev/null || true
	-killall ClaudeUsageTray 2>/dev/null || true
	rm -rf "$(APP)"
	@echo "Удалено: $(APP) и автозапуск сняты."

clean:
	swift package clean
	rm -rf .build/ClaudeUsageTray.app
