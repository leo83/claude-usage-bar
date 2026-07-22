import AppKit
import Foundation

/// Renders the Claude "sparkle" mark, then three usage bars, each with its
/// letter (s / w / f …) placed *inside* the bar with adaptive contrast.
///
/// Two modes:
/// - **monochrome** (default): a *template* image — macOS tints it black on a
///   light menu bar, white on a dark one. Track vs fill is conveyed by opacity.
///   The in-bar letter is knocked out of the fill (transparent) when it sits
///   over the filled part, or drawn solid when it sits over the empty track.
/// - **colored**: Claude-orange sparkle + severity-colored bars (not a template);
///   the letter is white over fill, dark over track.
enum BarsRenderer {
    private static let barCount = 3
    private static let barWidth: CGFloat = 7
    private static let innerGap: CGFloat = 2
    private static let sideInset: CGFloat = 1
    private static let height: CGFloat = 18
    private static let vInset: CGFloat = 0
    private static let corner: CGFloat = 1.5

    /// Narrow (condensed) letters, Stats-style.
    private static let letterFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 8, weight: .bold)
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.width: -0.4]
        ])
        return NSFont(descriptor: descriptor, size: 8) ?? base
    }()

    // Claude sparkle mark before the bars.
    private static let iconWidth: CGFloat = 11
    private static let iconHeight: CGFloat = 12
    private static let iconGap: CGFloat = 3

    private static let trackAlpha: CGFloat = 0.28
    private static let fillAlpha: CGFloat = 1.0

    private static let claudeOrange = NSColor(srgbRed: 0.847, green: 0.451, blue: 0.337, alpha: 1)

    private static var barsWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * innerGap
    }
    /// Leading offset of the bars: past the sparkle when shown, else just the inset.
    private static func barsOriginX(showIcon: Bool) -> CGFloat {
        showIcon ? sideInset + iconWidth + iconGap : sideInset
    }
    private static func width(showIcon: Bool) -> CGFloat {
        barsOriginX(showIcon: showIcon) + barsWidth + sideInset
    }

    private static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    /// Main entry. When `countdown` is non-nil (a limit fully blocks work), the
    /// bars are replaced by the countdown text — red in colored mode.
    static func image(for bars: [BarSpec], monochrome: Bool, showLetters: Bool, showIcon: Bool, countdown: String?) -> NSImage {
        if let countdown = countdown {
            return renderCountdown(countdown, monochrome: monochrome, showIcon: showIcon)
        }
        return renderBars(for: bars, monochrome: monochrome, showLetters: showLetters, showIcon: showIcon)
    }

    private static func renderBars(for bars: [BarSpec], monochrome: Bool, showLetters: Bool, showIcon: Bool) -> NSImage {
        let fractions: [CGFloat?] = (0..<barCount).map { index in
            index < bars.count ? max(0, min(1, CGFloat(bars[index].percent / 100))) : nil
        }
        let letters: [String] = showLetters
            ? (0..<barCount).map { index in index < bars.count ? bars[index].letter : "" }
            : Array(repeating: "", count: barCount)
        let fillColors: [NSColor]? = monochrome ? nil : (0..<barCount).map { index in
            index < bars.count ? severityColor(bars[index]) : .clear
        }
        return render(fractions: fractions, letters: letters, fillColors: fillColors, showIcon: showIcon)
    }

    /// Sparkle + countdown text (used when a limit fully blocks work).
    private static func renderCountdown(_ text: String, monochrome: Bool, showIcon: Bool) -> NSImage {
        let str = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: countdownFont]
        let textSize = str.size(withAttributes: attrs)
        let textOriginX = barsOriginX(showIcon: showIcon)
        let w = textOriginX + ceil(textSize.width) + sideInset
        let size = NSSize(width: w, height: height)

        let textColor: NSColor = monochrome ? .black : .systemRed
        let iconColor = monochrome ? NSColor.black.withAlphaComponent(fillAlpha) : claudeOrange

        let image = NSImage(size: size, flipped: false) { _ in
            if showIcon {
                let iconRect = NSRect(x: sideInset, y: (height - iconHeight) / 2,
                                      width: iconWidth, height: iconHeight)
                drawSparkle(in: iconRect, color: iconColor)
            }

            let origin = NSPoint(x: textOriginX, y: (height - textSize.height) / 2)
            str.draw(at: origin, withAttributes: [.font: countdownFont, .foregroundColor: textColor])
            return true
        }
        image.isTemplate = monochrome
        return image
    }

    /// Neutral placeholder (empty tracks + letters) before the first fetch / on error.
    static func placeholder(monochrome: Bool, showLetters: Bool, showIcon: Bool) -> NSImage {
        render(fractions: Array(repeating: nil, count: barCount),
               letters: showLetters ? ["s", "w", ""] : ["", "", ""],
               fillColors: monochrome ? nil : [], showIcon: showIcon)
    }

    /// `fillColors == nil` selects monochrome/template rendering.
    private static func render(fractions: [CGFloat?], letters: [String], fillColors: [NSColor]?, showIcon: Bool) -> NSImage {
        let monochrome = (fillColors == nil)
        let size = NSSize(width: width(showIcon: showIcon), height: height)
        let usableHeight = height - vInset * 2
        let barsOriginX = barsOriginX(showIcon: showIcon)

        let image = NSImage(size: size, flipped: false) { _ in
            // Claude sparkle (optional).
            if showIcon {
                let iconRect = NSRect(x: sideInset, y: (height - iconHeight) / 2,
                                      width: iconWidth, height: iconHeight)
                let iconColor = monochrome ? NSColor.black.withAlphaComponent(fillAlpha) : claudeOrange
                drawSparkle(in: iconRect, color: iconColor)
            }

            for index in 0..<barCount {
                let x = barsOriginX + CGFloat(index) * (barWidth + innerGap)

                // Track (faint, full height).
                let track = NSRect(x: x, y: vInset, width: barWidth, height: usableHeight)
                let trackColor = monochrome
                    ? NSColor.black.withAlphaComponent(trackAlpha)
                    : NSColor.tertiaryLabelColor
                trackColor.setFill()
                NSBezierPath(roundedRect: track, xRadius: corner, yRadius: corner).fill()

                // Fill (solid, proportional).
                let fraction = (index < fractions.count) ? fractions[index] : nil
                let fillHeight = (fraction ?? 0) > 0 ? max(1, usableHeight * (fraction ?? 0)) : 0
                if fillHeight > 0 {
                    let fill = NSRect(x: x, y: vInset, width: barWidth, height: fillHeight)
                    let fillColor = monochrome
                        ? NSColor.black.withAlphaComponent(fillAlpha)
                        : (index < (fillColors?.count ?? 0) ? fillColors![index] : .clear)
                    fillColor.setFill()
                    NSBezierPath(roundedRect: fill, xRadius: corner, yRadius: corner).fill()
                }

                // Letter inside the bar, centered, with adaptive contrast.
                guard index < letters.count, !letters[index].isEmpty else { continue }
                let letterCenter = NSPoint(x: x + barWidth / 2, y: vInset + usableHeight / 2)
                let overFill = fillHeight >= usableHeight / 2
                drawLetterInside(letters[index], center: letterCenter,
                                 monochrome: monochrome, overFill: overFill)
            }
            return true
        }
        image.isTemplate = monochrome
        return image
    }

    private static func drawLetterInside(_ s: String, center: NSPoint, monochrome: Bool, overFill: Bool) {
        let str = s as NSString
        let sizingAttrs: [NSAttributedString.Key: Any] = [.font: letterFont]
        let textSize = str.size(withAttributes: sizingAttrs)
        let origin = NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)

        guard let ctx = NSGraphicsContext.current else { return }

        if monochrome {
            if overFill {
                // Knock the glyph out of the solid fill → reads as menu-bar bg.
                let previous = ctx.compositingOperation
                ctx.compositingOperation = .destinationOut
                str.draw(at: origin, withAttributes: [.font: letterFont, .foregroundColor: NSColor.black])
                ctx.compositingOperation = previous
            } else {
                // Solid dark glyph over the faint track.
                str.draw(at: origin, withAttributes: [.font: letterFont, .foregroundColor: NSColor.black])
            }
        } else {
            let color: NSColor = overFill ? .white : .labelColor
            str.draw(at: origin, withAttributes: [.font: letterFont, .foregroundColor: color])
        }
    }

    /// A radiating sparkle/asterisk reminiscent of the Claude mark.
    private static func drawSparkle(in rect: NSRect, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY
        let radius = min(rect.width, rect.height) / 2
        let spokes = 12

        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = max(1, radius * 0.26)
        path.lineCapStyle = .round
        for i in 0..<spokes {
            let angle = (Double.pi * 2 / Double(spokes)) * Double(i)
            let inner = radius * 0.15
            let outer = radius * 0.98
            let x1 = cx + CGFloat(cos(angle)) * inner
            let y1 = cy + CGFloat(sin(angle)) * inner
            let x2 = cx + CGFloat(cos(angle)) * outer
            let y2 = cy + CGFloat(sin(angle)) * outer
            path.move(to: NSPoint(x: x1, y: y1))
            path.line(to: NSPoint(x: x2, y: y2))
        }
        path.stroke()
    }

    private static func severityColor(_ bar: BarSpec) -> NSColor {
        switch bar.severity.lowercased() {
        case "warning":
            return .systemOrange
        case "critical", "blocked", "exceeded", "over_limit":
            return .systemRed
        default:
            if bar.percent >= 95 { return .systemRed }
            if bar.percent >= 80 { return .systemOrange }
            return .systemGreen
        }
    }
}
