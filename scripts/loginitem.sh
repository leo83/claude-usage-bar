#!/usr/bin/env bash
# Портируемая регистрация автозапуска через per-user LaunchAgent.
#
# Ничего машинно-специфичного не захардкожено: label и исполняемый файл
# берутся из Info.plist самого бандла, путь к .app передаётся аргументом.
# Форк с другим именем/идентификатором работает без правок скрипта.
#
# Использование:
#   scripts/loginitem.sh on  /path/to/App.app   # включить автозапуск
#   scripts/loginitem.sh off /path/to/App.app   # выключить (bootout + удалить plist)
set -euo pipefail

ACTION="${1:-}"
APP="${2:-}"

if [[ -z "$ACTION" || -z "$APP" ]]; then
    echo "usage: $0 <on|off> <path-to-.app>" >&2
    exit 2
fi

INFO="$APP/Contents/Info.plist"
if [[ ! -f "$INFO" ]]; then
    echo "Не найден бандл: $APP (сначала выполните make install)" >&2
    exit 1
fi

LABEL="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")"
BIN="$APP/Contents/MacOS/$EXE"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

# Всегда снимаем прежнюю регистрацию, чтобы не плодить дубликаты.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [[ "$ACTION" == "off" ]]; then
    rm -f "$PLIST"
    echo "Автозапуск выключен: $LABEL"
    exit 0
fi

if [[ "$ACTION" != "on" ]]; then
    echo "Неизвестное действие: $ACTION (ожидается on|off)" >&2
    exit 2
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>                  <string>$LABEL</string>
    <key>ProgramArguments</key>       <array><string>$BIN</string></array>
    <key>RunAtLoad</key>              <true/>
    <key>KeepAlive</key>              <false/>
    <key>ProcessType</key>            <string>Interactive</string>
    <key>LimitLoadToSessionType</key> <string>Aqua</string>
</dict>
</plist>
PLIST

launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Автозапуск включён: $PLIST -> $BIN"
