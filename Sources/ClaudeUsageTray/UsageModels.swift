import Foundation

/// Response of GET https://api.anthropic.com/api/oauth/usage
/// We only decode the `limits` array — it is exactly what the interactive
/// `/usage` command renders (session / weekly-all / weekly-scoped).
struct UsageResponse: Decodable {
    let limits: [Limit]
}

struct Limit: Decodable {
    let kind: String        // "session" | "weekly_all" | "weekly_scoped"
    let group: String       // "session" | "weekly"
    let percent: Double
    let severity: String    // "normal" | "warning" | "critical" | ...
    let resets_at: String?
    let scope: Scope?
    let is_active: Bool?
}

struct Scope: Decodable {
    let model: ModelInfo?
}

struct ModelInfo: Decodable {
    let display_name: String?
}

// MARK: - View model

/// One rendered bar with everything the icon and tooltip need.
struct BarSpec {
    let label: String
    let letter: String      // one-char cap shown above the bar: s / w / f …
    let percent: Double
    let severity: String
    let resetsAt: Date?

    /// True when this limit fully blocks work (hit/exceeded), not merely warning.
    ///
    /// Blocking means the limit is actually exhausted (`percent >= 100`). The
    /// `severity` ladder tops out at `critical`, which the API reports well
    /// before exhaustion (≈90%) — that is a strong *warning*, not a block, so
    /// it must not trigger the "лимит исчерпан" countdown. Only an explicit
    /// exceeded/blocked severity (should it ever appear) also blocks.
    var isBlocking: Bool {
        if percent >= 100 { return true }
        switch severity.lowercased() {
        case "exceeded", "over_limit", "blocked", "exhausted":
            return true
        default:   // normal / warning / critical / "" → not blocking
            return false
        }
    }
}

enum UsageMapper {
    /// Canonical ordering for the three menu-bar bars.
    private static let order = ["session", "weekly_all", "weekly_scoped"]

    static func bars(from limits: [Limit]) -> [BarSpec] {
        let sorted = limits.sorted { a, b in
            (order.firstIndex(of: a.kind) ?? 99) < (order.firstIndex(of: b.kind) ?? 99)
        }
        return sorted.map { limit in
            BarSpec(
                label: label(for: limit),
                letter: letter(for: limit),
                percent: limit.percent,
                severity: limit.severity,
                resetsAt: parseDate(limit.resets_at)
            )
        }
    }

    /// One-character cap shown above the bar.
    private static func letter(for limit: Limit) -> String {
        switch limit.kind {
        case "session":
            return "s"
        case "weekly_all":
            return "w"
        case "weekly_scoped":
            // First letter of the scoped model (Fable → f, Opus → o, …).
            if let first = limit.scope?.model?.display_name?.first {
                return String(first).lowercased()
            }
            return "m"
        default:
            return String(limit.kind.prefix(1))
        }
    }

    private static func label(for limit: Limit) -> String {
        switch limit.kind {
        case "session":
            return "Сессия (5ч)"
        case "weekly_all":
            return "Неделя (все модели)"
        case "weekly_scoped":
            if let model = limit.scope?.model?.display_name, !model.isEmpty {
                return "Неделя (\(model))"
            }
            return "Неделя (модель)"
        default:
            return limit.kind
        }
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
