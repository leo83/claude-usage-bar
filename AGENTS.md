# AGENTS.md

Инструкции для AI-агентов и разработчиков, работающих с репозиторием
**claude-usage-tray**. Человеческое onboarding — в [README.md](README.md);
здесь — сжатый контекст, инварианты и запреты.

## Назначение проекта

Приложение для macOS в системном трее (menu bar). Показывает **три столбика**
использования лимитов Claude — те же, что рисует `/usage` в Claude Code:
`session` (5ч) · `weekly_all` (неделя, все модели) · `weekly_scoped` (неделя,
конкретная модель). При наведении — детальный тултип, по клику — меню с
действиями. В настройках — прокси (с авторизацией) и интервал опроса.

## Архитектура

```
main.swift ──▶ AppDelegate (NSStatusItem, Timer, меню, тултип)
                    │  каждые N сек
                    ▼
              UsageClient.fetch ──▶ GET /api/oauth/usage
                    │                   ▲  Bearer token   ▲ proxy + proxy-auth
                    │                   │                  │
                    │             Credentials         Settings.activeProxy
                    │           (security CLI)         (ProxyEnv парсинг)
                    ▼
             UsageMapper.bars([Limit]) ──▶ [BarSpec] ──▶ BarsRenderer → NSImage
                                                      └─▶ tooltip / menu текст
```

Приложение — **accessory** (без Dock-иконки): `NSApp.setActivationPolicy(.accessory)`
в `main.swift`, плюс `LSUIElement=true` в `Info.plist` бандла.

## Стек

| Часть | Технологии |
|-------|------------|
| Язык | Swift 5.9+ (тулчейн 6.x), таргет macOS 13 |
| UI | AppKit — `NSStatusItem`, `NSMenu`, `NSWindow`, `NSGridView` |
| Сеть | `URLSession` (ephemeral), прокси через `connectionProxyDictionary` + `URLSessionTaskDelegate` |
| Автозапуск | `ServiceManagement` / `SMAppService` (нужен `.app`-бандл) |
| Сборка | Swift Package Manager; `bundle.sh` собирает slices раздельно и `lipo`-ит в universal (две `--arch` сразу требуют Xcode/xcbuild); `Makefile` — склейка `.app` и install |

## Ключевые файлы

| Путь | Назначение |
|------|------------|
| `main.swift` | Вход; accessory-политика; флаги `--selftest` / `--probe` до старта GUI |
| `AppDelegate.swift` | `NSStatusItem`, таймер опроса, построение меню, тултип, toggle автозапуска |
| `UsageClient.swift` | HTTP-запрос, конфиг прокси, `ProxyAuthDelegate` (ответ на 407), маппинг ошибок в `UsageError` |
| `UsageModels.swift` | `UsageResponse`/`Limit`/`Scope`, `BarSpec` (цвет по severity), `UsageMapper` (порядок + подписи + парсинг дат) |
| `Credentials.swift` | Токен: сначала `~/.claude/.credentials.json`, затем Keychain через `/usr/bin/security`; разбор bare-token или JSON |
| `BarsRenderer.swift` | Отрисовка звезды Claude + столбиков (узкие буквы внутри, адаптивный контраст) + режим отсчёта вместо баров при блокировке; monochrome template / цветной; флаг `showLetters` |
| `Settings.swift` | `UserDefaults`: `proxyEnabled`/`proxyURL`/`pollSeconds`/`monochrome`/`showLetters`; `adoptEnvProxyIfEmpty`; `activeProxy` |
| `ProxyEnv.swift` | Чтение прокси из env, а если пусто — из **login-shell** (`$SHELL -lic`); `ProxyConfig` (парсинг URL с кредами) |
| `SettingsWindowController.swift` | Окно настроек: прокси-URL, интервал, цвет, показ букв |
| `SelfTest.swift` | `--selftest` (JSON→бары + растеризация рендера) и `--probe` (живой путь) |
| `scripts/bundle.sh` | Сборка **universal** (`lipo` arm64+x86_64) `.app` + Info.plist + ad-hoc `codesign` |

## Источник данных (инварианты)

- Endpoint: `GET https://api.anthropic.com/api/oauth/usage`, заголовки
  `Authorization: Bearer <token>` и `anthropic-beta: oauth-2025-04-20`.
- **Источник истины для баров — массив `limits[]`**, НЕ поля `five_hour`/
  `seven_day` (они дублируют часть данных без scoped-модели и severity).
- Порядок баров фиксирован: `session`, `weekly_all`, `weekly_scoped`
  (`UsageMapper.order`). Подпись scoped-бара — из `scope.model.display_name`
  динамически (модель меняется).
- Endpoint **недокументированный**. При его изменении правится только
  `UsageModels` + `UsageClient`; остальное не зависит от формата.

## Токен и Keychain (инварианты)

- Источники токена по порядку: **файл `~/.claude/.credentials.json`**
  (`claudeAiOauth.accessToken`), затем **Keychain через `/usr/bin/security
  find-generic-password -s 'Claude Code-credentials' -w`** — а не
  Security.framework — намеренно: ACL Keychain-prompt привязывается к
  стабильному Apple-подписанному `security`, поэтому одно «Always Allow»
  переживает пересборки неподписанного бинарника. **Не менять на прямой
  `SecItemCopyMatching`** без осознанного решения по ACL.
- Item хранит **только access-токен** (без refresh). Приложение перечитывает
  Keychain **перед каждым запросом**; обновление токена делает Claude Code
  (проверено: протухший токен снова становится валиден). Свой OAuth-refresh
  не реализуем без явной необходимости.
- На 401/403 → состояние `UsageError.unauthorized` (приглушённые бары + подсказка
  «откройте Claude Code»).

## Прокси (инварианты)

- Хранится как **полный URL** в формате `HTTPS_PROXY`
  (`http://user:pass@host:port`) — 1:1 с окружением, включая креды.
- Аутентификация прокси — через `ProxyAuthDelegate` (Basic/Digest/NTLM).
  Server-trust и прочие challenge → `performDefaultHandling` (иначе ломается TLS).
- Авто-подхват из env: `adoptEnvProxyIfEmpty()` на каждом старте — если в
  `proxyURL` нет валидного прокси (`ProxyConfig == nil`), берём из окружения.
  GUI из Finder env не наследует, поэтому `ProxyEnv` читает **login-shell**
  (`$SHELL -lic`) — работает независимо от способа запуска. Кнопки «взять из
  env» больше нет — детект автоматический; валидный ручной URL всегда сохраняется.

## Запреты

- **Никогда не логировать/печатать токен и пароль прокси.** `--probe` печатает
  только длину токена и `user:***` — сохранять этот принцип.
- Не хранить секреты где-либо, кроме `UserDefaults` proxy-URL (это осознанный
  компромисс для личного инструмента) и Keychain (токен — только чтение).
- `BarsRenderer`: `isTemplate` завязан на режим — `true` только в monochrome
  (система тинтит; трек/заливка различаются альфой), `false` в цветном (иначе
  потеряются severity-цвета и оранжевый Claude). Не хардкодить одно значение.
  Раскладка фиксирована: **звезда → столбики** (звезда перед барами). Буквы —
  ВНУТРИ бара: над заливкой выбиваются (`.destinationOut`), над треком —
  сплошные; в цветном белые/тёмные.
- Полная блокировка (`BarSpec.isBlocking`: **percent ≥ 100** ИЛИ явная severity
  `exceeded`/`over_limit`/`blocked`/`exhausted`) → вместо баров рисуется отсчёт
  `H:MM` (красный в цветном режиме). Отсчёт обновляет **отдельный поминутный
  `minuteTimer`** в `AppDelegate` из кэша `lastBars`, независимо от интервала
  опроса. **`critical` НЕ блокирует** — API отдаёт его ≈90%, это верхняя ступень
  предупреждения, а не исчерпание (иначе ложный «лимит исчерпан»).
- Транзиентные ошибки (`UsageError.isTransient`: 429 / 5xx / сеть) **не стирают**
  последнее удачное чтение — `AppDelegate` держит `lastBars` на экране, помечая
  их устаревшими («⚠️ данные от HH:MM · <ошибка>» в тултипе и меню), и
  восстанавливается на следующем опросе. Actionable-ошибки (`noToken`,
  `unauthorized`) — наоборот, показываются явно (плейсхолдер + текст), чтобы
  пользователь знал, что надо открыть Claude Code.
- Не блокировать главный поток на семафоре, ожидая completion из
  `DispatchQueue.main.async` (дедлок; в `--probe` крутится `RunLoop.main`).

## Что тестировать / команды

```bash
make selftest   # разбор реального JSON в три бара (без сети/GUI)
make probe      # живой путь: Keychain → (proxy) → HTTPS → decode
swift build     # чистая компиляция
make run        # ручная проверка иконки/тултипа/меню в трее
make install    # .app в /Applications (нужно для проверки автозапуска)
```

После **значимых** изменений (новый источник данных, изменение контракта ответа,
новая настройка, смена способа чтения токена/прокси) — обновляй **и** `README.md`,
**и** этот файл.
