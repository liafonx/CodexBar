import AppKit
import CodexBarCore

// MARK: - Layout

enum FloatingUsagePillLayout {
    static let ringDiameter: CGFloat = 54
    static let gutter: CGFloat = 8
    /// Same padding on every side, so the capsule ends share a centre with the rings.
    static let sidePadding: CGFloat = 6
    static let height: CGFloat = ringDiameter + 2 * sidePadding
    static let ringLineWidth: CGFloat = 4.5
    /// Space between the weekly ring and the session ring.
    static let ringGap: CGFloat = 1.5
    /// Space between two day segments, measured between their round caps.
    static let segmentGap: CGFloat = 1.5
    static let weeklyFontSize: CGFloat = 10.5
    static let sessionFontSize: CGFloat = 8
    /// Smallest size a reset countdown shrinks to when no unit choice fits inside the session ring.
    static let minCountdownFontSize: CGFloat = 5
    /// Clear space between a reset countdown and the inner edge of the session ring, so it never touches the pace tick.
    static let countdownClearance: CGFloat = 1
    /// Longest angle over which a ring fill fades into the pace color.
    static let blendLead: CGFloat = 1.2
    /// When the fill stops short of the pace point, its color starts to turn this far before the fill end.
    static let paceColorLeadIn: CGFloat = 0.6
    /// When the fill stops short of the pace point, its opacity starts to drop this far before the fill end,
    static let paceOpacityLeadIn: CGFloat = 0.25
    /// and reaches the pace arc opacity this far past it.
    static let paceOpacityLeadOut: CGFloat = 0.7
    /// A capsule: the ends are concentric with the rings.
    static let cornerRadius: CGFloat = height / 2
    static let hairlineWidth: CGFloat = 0.5
    static let highlightWidth: CGFloat = 1
    static let dragThreshold: CGFloat = 3

    static func size(columnCount: Int) -> CGSize {
        let columns = CGFloat(max(1, columnCount))
        let width = columns * self.ringDiameter + (columns - 1) * self.gutter + 2 * self.sidePadding
        return CGSize(width: width, height: self.height)
    }
}

// MARK: - Colors

enum FloatingUsagePillPalette {
    /// Opacity of the empty part of a ring, in the provider color.
    static let trackAlpha: CGFloat = 0.22
    /// Opacity of the arc between the fill end and the pace point, when the fill stops short of it.
    static let paceArcAlpha: CGFloat = 0.6

    /// Red when usage runs ahead of time, green when it runs behind, nothing on track.
    /// Mixes two colors in OKLab, which keeps lightness even and avoids the dark, muddy middle of an sRGB mix.
    /// Hue is not interpolated, so the fade never passes through unrelated colors.
    static func mix(_ from: NSColor, _ to: NSColor, _ fraction: CGFloat) -> NSColor {
        let start = OKLCH(from)
        let end = OKLCH(to)
        let (startA, startB) = (start.chroma * cos(start.hue), start.chroma * sin(start.hue))
        let (endA, endB) = (end.chroma * cos(end.hue), end.chroma * sin(end.hue))
        let labA = startA + (endA - startA) * fraction
        let labB = startB + (endB - startB) * fraction
        return OKLCH(
            lightness: start.lightness + (end.lightness - start.lightness) * fraction,
            chroma: hypot(labA, labB),
            hue: atan2(labB, labA)).color
    }

    /// Same red and green as the pace stripe on the menu usage bars.
    static func paceColor(for tone: FloatingUsagePillModel.Tone) -> NSColor? {
        switch tone {
        case .neutral: nil
        case .deficit: .systemRed
        case .reserve: .systemGreen
        }
    }

    static func providerColor(_ provider: UsageProvider) -> NSColor {
        let color = ProviderAccentPalette.color(for: provider)
        return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}

// MARK: - Rim

/// Transparent view that draws the glass edge over the custom backdrop. The pill and its hover panel share it.
final class FloatingUsagePillRimView: NSView {
    var cornerRadius: CGFloat = FloatingUsagePillLayout.cornerRadius {
        didSet { self.needsDisplay = true }
    }

    /// The panel edge runs light around the top corners and fades down the sides, like a desktop widget.
    var wrapsCorners = false {
        didSet { self.needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }

    private var isDark: Bool {
        self.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Glass edge like the Dock and system buttons: light along the top and bottom edges, dark along the
    /// left and right edges, each strongest at its middle and fading out toward the corners. Fainter
    /// copies further in give a soft transition into the inner area instead of a hard line.
    override func draw(_: NSRect) {
        let steps: [(inset: CGFloat, strength: CGFloat)] = [(0, 1), (0.5, 0.45), (1, 0.22), (1.5, 0.1), (2, 0.04)]
        for step in steps {
            self.drawRimLine(inset: step.inset, strength: step.strength)
        }
        // Light mode adds a faint dark hairline along the outer edge, so the shape stays clear on light content.
        if !self.isDark {
            let outlineWidth: CGFloat = 0.5
            let offset = outlineWidth / 2
            let outline = NSBezierPath(
                roundedRect: self.bounds.insetBy(dx: offset, dy: offset),
                xRadius: max(0, self.cornerRadius - offset),
                yRadius: max(0, self.cornerRadius - offset))
            outline.lineWidth = outlineWidth
            NSColor(white: 0, alpha: 0.18).setStroke()
            outline.stroke()
        }
    }

    private func drawRimLine(inset: CGFloat, strength: CGFloat) {
        let width: CGFloat = 0.5
        let radius = self.cornerRadius
        let offset = inset + width / 2
        let rim = NSBezierPath(
            roundedRect: self.bounds.insetBy(dx: offset, dy: offset),
            xRadius: max(0, radius - offset),
            yRadius: max(0, radius - offset))
        let stroked = rim.cgPath.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        guard let context = NSGraphicsContext.current?.cgContext,
              let light = NSGradient(colors: [
                  NSColor(white: 1, alpha: 0),
                  NSColor(white: 1, alpha: (self.isDark ? 0.55 : 1) * strength),
                  NSColor(white: 1, alpha: 0),
              ]),
              let dark = NSGradient(colors: [
                  NSColor(white: 0, alpha: 0),
                  NSColor(white: 0, alpha: 0.35 * strength),
                  NSColor(white: 0, alpha: 0),
              ])
        else { return }
        let bounds = self.bounds
        context.saveGState()
        context.addPath(stroked)
        context.clip()
        // Light mode keeps the plain top-and-bottom edge on the panel too: on a light panel the corner-only
        // edge is too faint, so the panel takes the bright top and bottom and the dark sides of the pill.
        if self.wrapsCorners, self.isDark {
            // Light along the top and bottom edges. Only the outer hairline turns the corners and fades down
            // the sides; the fainter inner lines stop where the corners begin, so the edge thins there.
            if strength < 1 {
                let span = max(1, bounds.width)
                // Gone by the point where the corner starts to curve, full well inside the flat edge.
                let start = min(0.45, radius / span)
                let full = min(0.5, radius * 2.5 / span)
                let band = NSGradient(
                    colorsAndLocations:
                    (NSColor(white: 1, alpha: 0), 0),
                    (NSColor(white: 1, alpha: 0), start),
                    (NSColor(white: 1, alpha: 0.6 * strength), full),
                    (NSColor(white: 1, alpha: 0.6 * strength), 1 - full),
                    (NSColor(white: 1, alpha: 0), 1 - start),
                    (NSColor(white: 1, alpha: 0), 1))
                band?.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: radius), angle: 0)
                band?.draw(
                    in: CGRect(x: bounds.minX, y: bounds.maxY - radius, width: bounds.width, height: radius),
                    angle: 0)
            } else {
                let corner = min(0.2, radius / max(1, bounds.height))
                NSGradient(
                    colorsAndLocations:
                    (NSColor(white: 1, alpha: 0.5), 0),
                    (NSColor(white: 1, alpha: 0.16), corner * 0.4),
                    (NSColor(white: 1, alpha: 0.04), corner * 0.9),
                    (NSColor(white: 1, alpha: 0), corner * 1.3),
                    (NSColor(white: 1, alpha: 0), 1 - corner * 1.3),
                    (NSColor(white: 1, alpha: 0.02), 1 - corner * 0.9),
                    (NSColor(white: 1, alpha: 0.08), 1 - corner * 0.4),
                    (NSColor(white: 1, alpha: 0.22), 1))?
                    .draw(in: bounds, angle: 90)
            }
            context.restoreGState()
            return
        }
        // Top and bottom bands fade horizontally; side bands fade vertically.
        light.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: radius), angle: 0)
        light.draw(in: CGRect(x: bounds.minX, y: bounds.maxY - radius, width: bounds.width, height: radius), angle: 0)
        dark.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: radius, height: bounds.height), angle: 90)
        dark.draw(in: CGRect(x: bounds.maxX - radius, y: bounds.minY, width: radius, height: bounds.height), angle: 90)
        context.restoreGState()
    }
}

// MARK: - Drawing view

/// Transparent view that draws the rings, percents and rim. It sits above the material view,
/// so the material (and Reduce Transparency's opaque fill) never covers the usage drawing.
private final class FloatingUsagePillDrawingView: NSView {
    var model = FloatingUsagePillModel(columns: []) {
        didSet { self.needsDisplay = true }
    }

    /// Liquid Glass draws its own edge, so the hand-drawn border is only for the older material.
    var drawsBorder = true

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    private func drawInnerHighlight() {
        self.strokeRim(
            colors: [
                NSColor(white: 1, alpha: 0.45),
                NSColor(white: 1, alpha: 0.12),
                NSColor(white: 1, alpha: 0.05),
            ],
            angle: self.isFlipped ? 90 : -90,
            width: FloatingUsagePillLayout.highlightWidth)
    }

    private func strokeRim(colors: [NSColor], angle: CGFloat, width: CGFloat) {
        let inset = FloatingUsagePillLayout.hairlineWidth + width / 2
        let radius = FloatingUsagePillLayout.cornerRadius - inset
        let rim = NSBezierPath(
            roundedRect: self.bounds.insetBy(dx: inset, dy: inset),
            xRadius: radius,
            yRadius: radius)
        rim.lineWidth = width
        let stroked = rim.cgPath.copy(
            strokingWithWidth: width,
            lineCap: .butt,
            lineJoin: .round,
            miterLimit: 10)
        guard let context = NSGraphicsContext.current?.cgContext,
              let gradient = NSGradient(colors: colors)
        else { return }
        context.saveGState()
        context.addPath(stroked)
        context.clip()
        gradient.draw(in: self.bounds, angle: angle)
        context.restoreGState()
    }

    override func draw(_: NSRect) {
        if self.drawsBorder {
            self.drawBorder()
        }
        self.drawColumns()
    }

    private func drawBorder() {
        let outline = NSBezierPath(
            roundedRect: self.bounds.insetBy(
                dx: FloatingUsagePillLayout.hairlineWidth / 2,
                dy: FloatingUsagePillLayout.hairlineWidth / 2),
            xRadius: FloatingUsagePillLayout.cornerRadius,
            yRadius: FloatingUsagePillLayout.cornerRadius)
        outline.lineWidth = FloatingUsagePillLayout.hairlineWidth
        NSColor(white: 0, alpha: 0.35).setStroke()
        outline.stroke()
        self.drawInnerHighlight()
    }

    private func drawColumns() {
        let layout = FloatingUsagePillLayout.self
        for (index, column) in self.model.columns.enumerated() {
            let center = CGPoint(
                x: layout.sidePadding + layout.ringDiameter / 2
                    + CGFloat(index) * (layout.ringDiameter + layout.gutter),
                y: self.bounds.midY)
            let color = FloatingUsagePillPalette.providerColor(column.provider)
            let session = column.rows.first.flatMap(\.self)
            let weekly = column.rows.count > 1 ? column.rows[1] : nil
            self.drawWeeklyRing(weekly, center: center, color: color)
            self.drawSessionRing(session, center: center, color: color)
            self.drawPercents(weekly: weekly, session: session, center: center)
        }
    }

    /// Outer ring: one round-capped segment per day, filled clockwise from 12 o'clock.
    private func drawWeeklyRing(_ row: FloatingUsagePillModel.Row?, center: CGPoint, color: NSColor) {
        let layout = FloatingUsagePillLayout.self
        let radius = layout.ringDiameter / 2 - layout.ringLineWidth / 2
        let count = row?.segmentCount ?? 7
        let step = 2 * CGFloat.pi / CGFloat(count)
        // Round caps reach half a line width past each end, so the gap leaves room for both caps.
        let inset = (layout.segmentGap + layout.ringLineWidth) / 2 / radius
        let filled = CGFloat(row?.barFraction ?? 0) * 2 * .pi
        let pace = CGFloat(row?.dashFraction ?? 0) * 2 * .pi
        let tone = row.flatMap { FloatingUsagePillPalette.paceColor(for: $0.tone) }
        let track = color.withAlphaComponent(FloatingUsagePillPalette.trackAlpha)
        let shade = tone.flatMap { Self.weeklyShade(color: color, tone: $0, filled: filled, pace: pace) }
        // Short of the pace point, the stroke runs on to the pace point; otherwise it stops at the fill end.
        let strokeLimit = tone != nil && filled < pace ? pace : filled
        for segment in 0..<count {
            let start = CGFloat(segment) * step + inset
            let end = CGFloat(segment + 1) * step - inset
            self.strokeArc(center: center, radius: radius, from: start, to: end, color: track)
            let strokeEnd = min(end, strokeLimit)
            guard strokeEnd > start else { continue }
            if let shade, strokeEnd > shade.firstChange {
                // One stroke per day, so the fill and the pace color never overlap at a seam.
                self.strokeBlendedArc(center: center, radius: radius, from: start, to: strokeEnd, color: shade.color)
            } else {
                self.strokeArc(center: center, radius: radius, from: start, to: strokeEnd, color: color)
            }
        }
    }

    /// Color and opacity along the weekly stroke, for a fill that is short of or past the pace point.
    private struct WeeklyShade {
        /// First angle where the stroke differs from the plain fill.
        let firstChange: CGFloat
        let color: (CGFloat) -> NSColor
    }

    private static func weeklyShade(color: NSColor, tone: NSColor, filled: CGFloat, pace: CGFloat) -> WeeklyShade? {
        let layout = FloatingUsagePillLayout.self
        if filled > pace {
            // The fill turns to the pace color over a soft seam centred on the pace point.
            let lead = layout.blendLead / 2
            return WeeklyShade(firstChange: pace - lead) { angle in
                FloatingUsagePillPalette.mix(color, tone, Self.ramp(angle, from: pace - lead, to: pace + lead))
            }
        }
        guard filled < pace else { return nil }
        // The fill runs on into a fainter arc in the pace color that ends at the pace point. Color and opacity
        // both start to change inside the fill, so the fill end falls in the middle of the fade, not at an edge.
        let span = pace - filled
        let colorStart = filled - min(layout.paceColorLeadIn, filled)
        let colorEnd = filled + min(layout.blendLead, span)
        let alphaStart = filled - min(layout.paceOpacityLeadIn, filled)
        // With no fill there is nothing to fade from, so the arc starts at its own opacity.
        let alphaEnd = filled > 0 ? filled + min(layout.paceOpacityLeadOut, span) : alphaStart
        let alphaDrop = 1 - FloatingUsagePillPalette.paceArcAlpha
        return WeeklyShade(firstChange: min(colorStart, alphaStart)) { angle in
            let mixed = FloatingUsagePillPalette.mix(color, tone, Self.ramp(angle, from: colorStart, to: colorEnd))
            return mixed.withAlphaComponent(1 - alphaDrop * Self.ramp(angle, from: alphaStart, to: alphaEnd))
        }
    }

    private static func ramp(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        guard upper > lower else { return 1 }
        let linear = min(1, max(0, (value - lower) / (upper - lower)))
        // Smootherstep: flat slope and curvature at both ends, so a fade has no visible start or end.
        return linear * linear * linear * (linear * (6 * linear - 15) + 10)
    }

    /// A tick across the ring band at the pace point, with a thin dark gap around it.
    private func drawPaceTick(at angle: CGFloat, center: CGPoint, radius: CGFloat, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let half = FloatingUsagePillLayout.ringLineWidth / 2 - 0.4
        let direction = CGPoint(x: sin(angle), y: -cos(angle))
        let outer = CGPoint(x: center.x + (radius + half) * direction.x, y: center.y + (radius + half) * direction.y)
        let inner = CGPoint(x: center.x + (radius - half) * direction.x, y: center.y + (radius - half) * direction.y)
        context.saveGState()
        context.setLineCap(.round)
        for (width, stroke) in [(2.6, NSColor(white: 0, alpha: 0.55)), (1.3, color)] {
            context.setLineWidth(width)
            context.setStrokeColor(stroke.cgColor)
            context.move(to: outer)
            context.addLine(to: inner)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// Clips to one round-capped arc and fills it with a conic gradient, so color and opacity can change along it.
    /// `color` takes a clockwise angle from 12 o'clock, clamped to `start...end`, and returns the color with its alpha.
    private func strokeBlendedArc(
        center: CGPoint,
        radius: CGFloat,
        from start: CGFloat,
        to end: CGFloat,
        color: (CGFloat) -> NSColor)
    {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let width = FloatingUsagePillLayout.ringLineWidth
        // The gradient turns a full circle from the point opposite the arc, so its wrap-around seam is clipped away.
        let origin = (start + end) / 2 - .pi
        // Stops cover the arc and its round caps, about one per half degree; the end colors fill the rest of the turn.
        let cap = width / 2 / radius
        let sweep = end - start + 2 * cap
        let samples = max(2, Int((sweep / (.pi / 360)).rounded(.up)) + 1)
        var colors = [color(start).cgColor]
        var locations: [CGFloat] = [0]
        for index in 0..<samples {
            let angle = start - cap + sweep * CGFloat(index) / CGFloat(samples - 1)
            colors.append(color(min(end, max(start, angle))).cgColor)
            locations.append((angle - origin) / (2 * .pi))
        }
        colors.append(color(end).cgColor)
        locations.append(1)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: locations)
        else { return }
        let arc = CGMutablePath()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: start - .pi / 2,
            endAngle: end - .pi / 2,
            clockwise: false)
        context.saveGState()
        context.addPath(arc.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
        context.clip()
        // macOS 14 API that Swift does not import as a CGContext method. The view is flipped, so the conic angle
        // runs clockwise on screen, like the arcs.
        CGContextDrawConicGradient(context, gradient, center, origin - .pi / 2)
        context.restoreGState()
    }

    /// Inner ring: one continuous round-capped arc, filled clockwise from 12 o'clock.
    private func drawSessionRing(_ row: FloatingUsagePillModel.Row?, center: CGPoint, color: NSColor) {
        let layout = FloatingUsagePillLayout.self
        let radius = layout.ringDiameter / 2 - layout.ringLineWidth * 1.5 - layout.ringGap
        let full = 2 * CGFloat.pi
        let track = color.withAlphaComponent(FloatingUsagePillPalette.trackAlpha)
        self.strokeArc(center: center, radius: radius, from: 0, to: full, color: track)
        guard let row else { return }
        let fraction = CGFloat(row.barFraction)
        if fraction > 0 {
            self.strokeArc(center: center, radius: radius, from: 0, to: min(1, fraction) * full, color: color)
        }
        if row.dashFraction > 0 {
            let tick = FloatingUsagePillPalette.paceColor(for: row.tone) ?? .white
            self.drawPaceTick(at: CGFloat(row.dashFraction) * full, center: center, radius: radius, color: tick)
        }
    }

    /// `from` and `to` are clockwise angles from 12 o'clock, in radians.
    private func strokeArc(center: CGPoint, radius: CGFloat, from start: CGFloat, to end: CGFloat, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setLineWidth(FloatingUsagePillLayout.ringLineWidth)
        context.setLineCap(.round)
        context.setStrokeColor(color.cgColor)
        // The view is flipped, so increasing angles run clockwise on screen.
        context.addArc(
            center: center,
            radius: radius,
            startAngle: start - .pi / 2,
            endAngle: end - .pi / 2,
            clockwise: false)
        context.strokePath()
        context.restoreGState()
    }

    /// Softer than full label black and white: #191919 / #F1F1F1 for weekly, #666 / #9C9C9C for session.
    private static let weeklyPercentColor = FloatingUsagePillDrawingView.percentColor(light: 0x19, dark: 0xF1)
    private static let sessionPercentColor = FloatingUsagePillDrawingView.percentColor(light: 0x66, dark: 0x9C)

    private static func percentColor(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let white = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat(white) / 255,
                green: CGFloat(white) / 255,
                blue: CGFloat(white) / 255,
                alpha: 1)
        }
    }

    private struct TextStyle {
        let size: CGFloat
        let weight: NSFont.Weight
        let color: NSColor

        func text(_ string: String, size: CGFloat? = nil) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size ?? self.size, weight: self.weight),
                .foregroundColor: self.color,
            ])
        }
    }

    /// Weekly percent in the centre, with the smaller, dimmer session percent under it. A used-up window shows the
    /// time to its reset in place of its percent.
    private func drawPercents(
        weekly: FloatingUsagePillModel.Row?,
        session: FloatingUsagePillModel.Row?,
        center: CGPoint)
    {
        let layout = FloatingUsagePillLayout.self
        let mainStyle = TextStyle(size: layout.weeklyFontSize, weight: .semibold, color: Self.weeklyPercentColor)
        let minorStyle = TextStyle(size: layout.sessionFontSize, weight: .medium, color: Self.sessionPercentColor)
        let main = mainStyle.text(Self.percentString(weekly?.barFraction))
        let minor = minorStyle.text(Self.percentString(session?.barFraction))
        let mainSize = main.size()
        let minorSize = minor.size()
        // The two lines overlap by a point of leading, so they read as one group.
        let top = center.y - (mainSize.height + minorSize.height - 1) / 2
        let lines = [
            (text: main, size: mainSize, row: weekly, style: mainStyle, top: top),
            (text: minor, size: minorSize, row: session, style: minorStyle, top: top + mainSize.height - 1),
        ]
        for line in lines {
            if let countdown = line.row?.resetCountdown, !countdown.isEmpty {
                let baseline = line.top + NSFont.monospacedDigitSystemFont(
                    ofSize: line.style.size,
                    weight: line.style.weight).ascender
                Self.drawCountdown(countdown, style: line.style, baseline: baseline, center: center)
            } else {
                line.text.draw(at: CGPoint(x: center.x - line.size.width / 2, y: line.top))
            }
        }
    }

    private static func percentString(_ fraction: Double?) -> String {
        fraction.map { "\(Int((min(1, max(0, $0)) * 100).rounded()))%" } ?? "–"
    }

    /// Draws the first countdown text that fits inside the session ring. When none fits, the last one shrinks until it
    /// does. The text keeps the baseline of its line and is centred on its ink.
    private static func drawCountdown(_ texts: [String], style: TextStyle, baseline: CGFloat, center: CGPoint) {
        let offset = baseline - center.y
        let measure = { (string: String, size: CGFloat) -> (text: NSAttributedString, ink: CGRect, size: CGFloat) in
            let text = style.text(string, size: size)
            let bounds = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            return (text, text.boundingRect(with: bounds, options: .usesDeviceMetrics), size)
        }
        var choice = texts.lazy.map { measure($0, style.size) }.first { Self.fits($0.ink, baselineOffset: offset) }
            ?? measure(texts[texts.count - 1], style.size)
        let minSize = FloatingUsagePillLayout.minCountdownFontSize
        while !Self.fits(choice.ink, baselineOffset: offset), choice.size > minSize {
            choice = measure(texts[texts.count - 1], choice.size - 0.25)
        }
        let ascender = NSFont.monospacedDigitSystemFont(ofSize: choice.size, weight: style.weight).ascender
        choice.text.draw(at: CGPoint(x: center.x - choice.ink.midX, y: baseline - ascender))
    }

    /// True when ink measured from its baseline, centred on the ring centre with the baseline `baselineOffset` below
    /// it, stays clear of the inner edge of the session ring.
    private static func fits(_ ink: CGRect, baselineOffset: CGFloat) -> Bool {
        let layout = FloatingUsagePillLayout.self
        let radius = layout.ringDiameter / 2 - 2 * layout.ringLineWidth - layout.ringGap - layout.countdownClearance
        // Ink rises from the baseline, and the view is flipped, so its top is the smaller offset.
        let reach = max(abs(baselineOffset - ink.maxY), abs(baselineOffset - ink.minY))
        return (ink.width / 2) * (ink.width / 2) + reach * reach <= radius * radius
    }
}

// MARK: - View

/// Hosts the popover material and the drawing view, and turns mouse input into callbacks.
final class FloatingUsagePillView: NSView {
    var model = FloatingUsagePillModel(columns: []) {
        didSet {
            guard self.model != oldValue else { return }
            self.refreshPresentation()
        }
    }

    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onInteractionBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private let drawingView = FloatingUsagePillDrawingView()
    private var dragStartMouse = CGPoint.zero
    private var dragStartOrigin = CGPoint.zero
    private var isDragging = false

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setUp()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUp() {
        self.wantsLayer = true
        let background = FloatingUsagePillGlass.makeBackground(
            cornerRadius: FloatingUsagePillLayout.cornerRadius,
            clear: true)
        // Liquid Glass draws its own edge, so the hand-drawn border is only for the older material.
        self.drawingView.drawsBorder = !FloatingUsagePillGlass.isAvailable
        background.frame = self.bounds
        background.autoresizingMask = [.width, .height]
        self.addSubview(background)
        self.drawingView.frame = self.bounds
        self.drawingView.autoresizingMask = [.width, .height]
        if FloatingUsagePillGlass.isAvailable {
            let rim = FloatingUsagePillRimView(frame: self.bounds)
            rim.autoresizingMask = [.width, .height]
            self.addSubview(rim, positioned: .above, relativeTo: background)
        }
        self.addSubview(self.drawingView, positioned: .above, relativeTo: nil)

        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.button)
        self.setAccessibilityLabel(L("floating_pill_accessibility_label"))
        self.refreshPresentation()
    }

    private func refreshPresentation() {
        let tooltips = self.model.columns.flatMap(\.tooltips).joined(separator: "\n")
        self.toolTip = tooltips
        self.setAccessibilityValue(tooltips)
        self.drawingView.model = self.model
    }

    // MARK: Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The effect view is a pure background; this view owns every event.
        self.bounds.contains(self.convert(point, from: self.superview)) ? self : nil
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in self.trackingAreas {
            self.removeTrackingArea(area)
        }
        self.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with _: NSEvent) {
        self.onHoverChanged?(true)
    }

    override func mouseExited(with _: NSEvent) {
        self.onHoverChanged?(false)
    }

    override func mouseDown(with _: NSEvent) {
        guard let window = self.window else { return }
        self.dragStartMouse = NSEvent.mouseLocation
        self.dragStartOrigin = window.frame.origin
        self.isDragging = false
    }

    override func mouseDragged(with _: NSEvent) {
        guard let window = self.window else { return }
        let mouse = NSEvent.mouseLocation
        let deltaX = mouse.x - self.dragStartMouse.x
        let deltaY = mouse.y - self.dragStartMouse.y
        if !self.isDragging {
            guard hypot(deltaX, deltaY) >= FloatingUsagePillLayout.dragThreshold else { return }
            self.isDragging = true
            self.onInteractionBegan?()
        }
        window.setFrameOrigin(CGPoint(x: self.dragStartOrigin.x + deltaX, y: self.dragStartOrigin.y + deltaY))
    }

    override func mouseUp(with _: NSEvent) {
        if self.isDragging {
            self.isDragging = false
            self.onDragEnded?()
        }
        // A plain left click does nothing: hover shows the cards, right click shows the app menu.
    }

    // MARK: Right click

    /// Right click opens a short app menu: Refresh, Settings, About and Quit.
    override func rightMouseDown(with _: NSEvent) {
        self.onInteractionBegan?()
        self.onRightClick?()
    }

    // MARK: Accessibility

    override func accessibilityPerformPress() -> Bool {
        guard let onClick = self.onClick else { return false }
        self.onInteractionBegan?()
        onClick()
        return true
    }
}

// MARK: - OKLCH

/// Perceptual color space for smooth color fades. Conversions follow Björn Ottosson's OKLab.
private struct OKLCH {
    let lightness: CGFloat
    let chroma: CGFloat
    let hue: CGFloat

    init(lightness: CGFloat, chroma: CGFloat, hue: CGFloat) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let (r, g, b) = (
            Self.linear(srgb.redComponent),
            Self.linear(srgb.greenComponent),
            Self.linear(srgb.blueComponent))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let labA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let labB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        self.lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        self.chroma = hypot(labA, labB)
        self.hue = atan2(labB, labA)
    }

    var color: NSColor {
        let labA = self.chroma * cos(self.hue)
        let labB = self.chroma * sin(self.hue)
        let l = pow(self.lightness + 0.3963377774 * labA + 0.2158037573 * labB, 3)
        let m = pow(self.lightness - 0.1055613458 * labA - 0.0638541728 * labB, 3)
        let s = pow(self.lightness - 0.0894841775 * labA - 1.2914855480 * labB, 3)
        return NSColor(
            srgbRed: Self.gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: Self.gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: Self.gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
            alpha: 1)
    }

    private static func linear(_ value: CGFloat) -> CGFloat {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ value: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, value))
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}
