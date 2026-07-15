.PHONY: build run app install launch clean selftest probe

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

clean:
	swift package clean
	rm -rf .build/ClaudeUsageTray.app
