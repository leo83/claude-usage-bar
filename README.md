# Claude Usage Tray

> A tiny macOS menu-bar app that shows your Claude usage as three live bars — the
> same limits you see in Claude Code's `/usage` command.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![arch](https://img.shields.io/badge/binary-universal%20(arm64%2Bx86__64)-blueviolet)
![language](https://img.shields.io/badge/Swift-5.9%2B-orange)
![license](https://img.shields.io/badge/license-Beerware%20🍺-yellow)

It sits in your menu bar and renders three vertical bars for the three Claude
rate limits. Hover for a detailed breakdown (percent + reset time), click for a
menu with the same details plus actions. Colors shift green → orange → red as a
limit fills up.

## Screenshots

The three live bars in the menu bar (the leftmost icon, with `s` / `w` / `f` letters):

![Menu-bar bars](docs/menubar.png)

Click for the full `/usage`-style breakdown and actions:

![Click menu](docs/menu.png)

When a limit is fully exhausted, the bars are replaced by a countdown to
unblock (`H:MM`, rounded up so the last minute still reads `0:01`):

![Limit reached — countdown to unblock](docs/blocked.png)

```
 menu bar:  ▁ ▄ █        ← session (5h) · week (all) · week (model)
                │
      hover ────┴──▶  Claude usage
                      • Сессия (5ч): 24%  · сброс вт 15 июл 18:19
                      • Неделя (все модели): 61%  · сброс пн 20 июл 19:59
                      • Неделя (Fable): 88%  · сброс пн 20 июл 19:59
```

---

## Features

- **Claude sparkle + three live bars** in the menu bar — session (5h), weekly
  (all models), weekly (per-model). Bar height = utilization, with a letter
  inside each bar (`s` / `w` / model initial, e.g. `f` for Fable).
- **Blocking countdown** — when a limit is fully exhausted, the bars are
  replaced by a `H:MM` countdown to unblock (red in colored mode), ticking every
  minute.
- **Two icon styles** — native monochrome template (default, follows light/dark
  menu bar) or colored severity bars — switchable in settings.
- **Hover tooltip** with the full `/usage`-style breakdown.
- **Click menu** with per-limit lines, manual refresh, settings, launch-at-login,
  and quit.
- **Show/hide letters** — toggle the in-bar letters in settings.
- **Proxy support**, including authenticated corporate proxies
  (`http://user:pass@host:port`, Basic/Digest/NTLM). Auto-detected from your
  `HTTPS_PROXY`/`HTTP_PROXY` — even when launched from Finder (read via your
  login shell), with no manual step.
- **Configurable poll interval** (default 60s).
- **Native, small & universal** — pure Swift/AppKit, no runtime bundled;
  ~660 KB universal `.app` (Apple Silicon + Intel).

## Quick Start

### Prerequisites

- macOS 13 or newer
- Xcode **Command Line Tools** (no full Xcode required): `xcode-select --install`
- [Claude Code](https://claude.com/claude-code) installed and signed in
  (the app reuses its Keychain token)

### Build & run

```bash
git clone <your-repo-url> claude-usage-tray
cd claude-usage-tray

# Dev run — the bars appear in your menu bar; Ctrl-C to stop.
make run
```

On first launch macOS asks once for permission to read the
`Claude Code-credentials` Keychain item — choose **Always Allow**.

### Install as an app

```bash
make install          # builds a signed .app and copies it to /Applications
open -a ClaudeUsageTray
```

To launch automatically at login, use the **«Запускать при входе»** toggle in the
menu (built-in `SMAppService`), or set up a portable per-user LaunchAgent:

```bash
make login     # enable launch at login
make unlogin   # disable
```

`make login` generates `~/Library/LaunchAgents/<bundle-id>.plist` from the
installed app's identifier and path (`scripts/loginitem.sh`) — nothing
machine-specific is stored in the repo, so forks with a different name or
identifier work unchanged.

### Uninstall

```bash
make uninstall
```

Removes launch-at-login and deletes `/Applications/ClaudeUsageTray.app`.

## Configuration

Click the menu-bar icon → **Настройки…**:

| Setting | Description |
|---------|-------------|
| **Прокси URL** | Full proxy URL in `HTTPS_PROXY` format, e.g. `http://user:pass@host:3128`. Empty = auto-detect from env. |
| **Интервал (сек)** | Poll interval in seconds (minimum 15). |
| **Цветные столбики** | On = severity colors (green/orange/red) + Claude-orange sparkle. Off (default) = monochrome native template icon that follows the menu-bar theme. |
| **Показывать буквы** | Show/hide the `s` / `w` / model-initial letters inside the bars. |

### Proxy from the environment

Whenever the proxy field is empty, the app auto-detects a proxy from the
environment, preferring `HTTPS_PROXY`, then `HTTP_PROXY`, then `ALL_PROXY`.

Apps launched from Finder/Spotlight don't inherit the shell environment, so the
app also queries your **login shell** (`$SHELL -lic`), which sources your
profile (`.zshrc`/`.zprofile`/`.bash_profile`) where the proxy is exported —
so detection works no matter how the app is launched. To use a different proxy,
just type it into the field (a valid entry is always kept).

## How it works

1. Every _N_ seconds the app sends `GET https://api.anthropic.com/api/oauth/usage`
   with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`.
2. The OAuth token is read from the macOS login Keychain item
   `Claude Code-credentials` by shelling out to `/usr/bin/security`. This binds
   the Keychain access prompt to Apple's stable, signed `security` binary, so a
   one-time **Always Allow** survives rebuilds of this (unsigned/ad-hoc) app.
3. The response's `limits` array — exactly what `/usage` renders — is mapped to
   three bars (`session`, `weekly_all`, `weekly_scoped`). The per-model bar's
   label comes from `scope.model.display_name` dynamically.

## Building a release bundle

```bash
make app        # → .build/ClaudeUsageTray.app (ad-hoc signed)
make selftest   # headless: decode a sample response into three bars
make probe      # headless: live Keychain → (proxy) → HTTPS → decode
make clean
```

`swift build` / `swift run` work directly too; the `Makefile` only adds the
`.app` bundling, install, and headless-check glue.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Bars are dimmed, tooltip says **«токен истёк»** | Access token expired and Claude Code hasn't refreshed it. Open Claude Code to refresh the session. |
| Tooltip says **«Токен не найден в Keychain»** | Claude Code isn't signed in, or you denied the Keychain prompt. Sign in, then allow access. |
| Repeated Keychain prompts | Choose **Always Allow** (not just "Allow"). |
| Proxy errors / `407` | Check the proxy URL includes credentials; verify with `make probe`. |
| Login-item toggle fails | `SMAppService` needs a real `.app` bundle — use `make install`, not the dev binary. |

## Limitations & caveats

- **The endpoint is undocumented and unofficial.** `/api/oauth/usage` is used
  internally by Claude Code and can change or break without notice. This is a
  personal tool, not a stable API client.
- **No OAuth refresh.** The app re-reads the Keychain each poll and relies on
  Claude Code to refresh and rewrite the token. If Claude Code hasn't run for a
  while, you'll see the "token expired" state until you open it.
- **Proxy string is stored in plaintext** in `UserDefaults` (same as your shell
  environment). Fine for a personal tool; don't commit exported settings.

## Project structure

```
Package.swift                     SwiftPM manifest (macOS 13+, one executable target)
Sources/ClaudeUsageTray/
  main.swift                      entry; accessory policy; --selftest / --probe flags
  AppDelegate.swift               status item, timer, menu, tooltip, launch-at-login
  UsageClient.swift               HTTP request + proxy + proxy auth + error mapping
  UsageModels.swift               response models + mapping to BarSpec
  Credentials.swift               token from ~/.claude/.credentials.json or Keychain
  BarsRenderer.swift              draws sparkle + bars (letters inside) / countdown
  Settings.swift                  UserDefaults (proxy, interval, style) + env adopt
  ProxyEnv.swift                  reads proxy from env / login shell; parses URL
  SettingsWindowController.swift  settings window
  SelfTest.swift                  headless checks (--selftest / --probe)
scripts/bundle.sh                 builds a universal .app (lipo) + ad-hoc codesign
Makefile                          build / run / app / install / selftest / probe
LICENSE                           Beerware
```

## Contributing

Issues and PRs welcome. Keep changes small and native. Before opening a PR:

```bash
make selftest   # JSON → bars mapping still holds
make probe      # live path still works (needs Claude Code signed in)
swift build     # compiles clean
```

See [AGENTS.md](AGENTS.md) for architecture invariants and contributor rules.

## Portability

- The bundled binary is **universal** (arm64 + x86_64), so it runs on both Apple
  Silicon and Intel Macs.
- The app has no machine-specific paths; it needs only Claude Code signed in on
  the same Mac (its Keychain item / `~/.claude/.credentials.json`).
- **Distribution:** the `.app` is **ad-hoc signed**, not notarized. The intended
  way to install is to build from source on your own Mac (`make install`) — a
  locally built app has no quarantine flag and launches normally. A prebuilt
  `.app` copied/downloaded to another Mac will be blocked by Gatekeeper
  ("unidentified developer"); open it via right-click → **Open** once, or run
  `xattr -dr com.apple.quarantine /Applications/ClaudeUsageTray.app`. Proper
  distribution would require a Developer ID signature + notarization.

## License

[Beerware](LICENSE) 🍺 — do whatever you want; if we meet, buy me a beer.
