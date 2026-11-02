import AppKit
import SwiftUI

// MARK: - Panels

private final class FloatingUsagePillPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Popover-material container for the hover cards that reports when the pointer enters or leaves it.
private final class FloatingUsagePillHoverContainer: NSView {
    var onHoverChanged: ((Bool) -> Void)?

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

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

// MARK: - Glass

/// One glass variant for the pill and the hover panel: regular Liquid Glass on macOS 26 and later,
/// the popover material before that.
enum FloatingUsagePillGlass {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// The pill and the hover panel use a backdrop of their own; `strength` sets how see-through it is.
    static func makeBackground(
        cornerRadius: CGFloat,
        clear: Bool = false,
        strength: FloatingUsagePillBackdropView.Strength = .pill) -> NSView
    {
        if clear, let backdrop = FloatingUsagePillBackdropView(cornerRadius: cornerRadius, strength: strength) {
            return backdrop
        }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = clear ? .clear : .regular
            glass.cornerRadius = cornerRadius
            return glass
        }
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = self.roundedMask(radius: cornerRadius)
        return effectView
    }

    /// A behind-window material ignores layer clipping, so the rounded shape comes from a mask image.
    /// The window shadow follows the same shape.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = 2 * radius + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A see-through backdrop with a light blur and a saturation boost, built from Core Animation's
/// window-server backdrop layer. System glass blurs too strongly for the pill; this keeps the
/// content behind it nearly sharp. Private classes: the initializer fails when they are missing.
final class FloatingUsagePillBackdropView: NSView {
    /// How much the backdrop hides what is behind it. The pill stays nearly sharp; the hover panel holds
    /// text, so it blurs and dims more.
    struct Strength {
        let blurRadius: CGFloat
        let dimming: CGFloat

        static let pill = Strength(blurRadius: 5, dimming: 0.1)
        static let panel = Strength(blurRadius: 10, dimming: 0.18)
    }

    static let saturation: CGFloat = 1.5

    init?(cornerRadius: CGFloat, strength: Strength = .pill) {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let blur = Self.makeFilter("gaussianBlur"),
              let saturate = Self.makeFilter("colorSaturate")
        else { return nil }
        super.init(frame: .zero)
        self.wantsLayer = true
        guard let layer = self.layer else { return nil }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        let backdrop = backdropClass.init()
        backdrop.setValue(true, forKey: "windowServerAware")
        backdrop.setValue(1.0, forKey: "scale")
        blur.setValue(strength.blurRadius, forKey: "inputRadius")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        saturate.setValue(Self.saturation, forKey: "inputAmount")
        backdrop.filters = [blur, saturate]
        backdrop.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.addSublayer(backdrop)

        let dim = CALayer()
        dim.backgroundColor = NSColor(white: 0, alpha: strength.dimming).cgColor
        dim.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.addSublayer(dim)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        for sublayer in self.layer?.sublayers ?? [] {
            sublayer.frame = self.bounds
        }
    }

    private static func makeFilter(_ type: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return nil }
        return filterClass.perform(selector, with: type)?.takeUnretainedValue() as? NSObject
    }
}

// MARK: - Hover content

struct FloatingUsagePillHoverContent: View {
    let models: [UsageMenuCardView.Model]
    let width: CGFloat

    private static let dividerWidth: CGFloat = 1

    /// Width of `count` cards in one row, with a divider between neighbours.
    static func totalWidth(cardCount count: Int, cardWidth: CGFloat) -> CGFloat {
        let cards = CGFloat(max(1, count))
        return cards * cardWidth + (cards - 1) * self.dividerWidth
    }

    /// Extra space above and below the cards, so the vertical margin matches the cards' 20 pt side margin.
    private static let verticalPadding: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(self.models.enumerated()), id: \.offset) { index, model in
                if index > 0 {
                    Divider()
                        .frame(width: Self.dividerWidth)
                }
                UsageMenuCardView(model: model, width: self.width)
                    .frame(width: self.width)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Self.verticalPadding)
        .frame(width: Self.totalWidth(cardCount: self.models.count, cardWidth: self.width))
        .foregroundStyle(MenuHighlightStyle.primary(false))
    }
}

// MARK: - Controller

/// Owns the floating pill panel and its hover card panel. It knows nothing about stores or menus.
@MainActor
final class FloatingUsagePillController {
    private static let hoverShowDelay: TimeInterval = 0.3
    private static let hoverHideDelay: TimeInterval = 0.3
    private static let refreshInterval: TimeInterval = 60
    private static let hoverGap: CGFloat = 6
    private static let hoverCornerRadius: CGFloat = 16
    private static let expandStartScale: CGFloat = 0.3
    private static let expandFadeDuration: TimeInterval = 0.16
    private static let collapseDuration: TimeInterval = 0.14

    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onTick: (() -> Void)?
    /// Builds the hover cards each time the panel is about to show.
    var hoverContentProvider: (() -> (models: [UsageMenuCardView.Model], width: CGFloat))?

    private let defaults: UserDefaults
    private let panel: FloatingUsagePillPanel
    private let pillView: FloatingUsagePillView
    private var hoverPanel: NSPanel?
    private var refreshTimer: Timer?
    private var hoverShowWork: DispatchWorkItem?
    private var hoverHideWork: DispatchWorkItem?
    private var pointerOnPill = false
    private var hoverSuppressed = false
    private var hoverGeneration = 0
    private var pointerOnHoverPanel = false
    private var screenObserver: NSObjectProtocol?

    var isVisible: Bool {
        self.panel.isVisible
    }

    /// The view that menus pop up from.
    var anchorView: NSView {
        self.pillView
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let size = FloatingUsagePillLayout.size(columnCount: 1)
        self.pillView = FloatingUsagePillView(frame: CGRect(origin: .zero, size: size))
        self.panel = FloatingUsagePillPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        self.panel.level = .floating
        // No `.fullScreenAuxiliary`: the pill stays out of full-screen Spaces.
        self.panel.collectionBehavior = [.canJoinAllSpaces]
        self.panel.isOpaque = false
        self.panel.backgroundColor = .clear
        // Liquid Glass draws its own edge and shadow; a window shadow on top doubles it.
        self.panel.hasShadow = !FloatingUsagePillGlass.isAvailable
        self.panel.hidesOnDeactivate = false
        self.panel.isReleasedWhenClosed = false
        self.panel.becomesKeyOnlyIfNeeded = true
        self.panel.contentView = self.pillView
        self.wirePillView()
        self.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated { self?.clampToVisibleScreens() }
        }
    }

    private func wirePillView() {
        self.pillView.onClick = { [weak self] in self?.onClick?() }
        self.pillView.onRightClick = { [weak self] in self?.onRightClick?() }
        self.pillView.onInteractionBegan = { [weak self] in
            // A drag or right click ends hovering until the pointer leaves the pill and comes back.
            self?.hoverSuppressed = true
            self?.hideHoverPanel()
        }
        self.pillView.onDragEnded = { [weak self] in
            self?.clampToVisibleScreens()
            self?.saveOrigin()
        }
        self.pillView.onHoverChanged = { [weak self] inside in
            if !inside { self?.hoverSuppressed = false }
            self?.pointerOnPill = inside
            self?.hoverChanged()
        }
    }

    // MARK: Showing

    func show(model: FloatingUsagePillModel) {
        self.pillView.model = model
        let size = FloatingUsagePillLayout.size(columnCount: model.columns.count)
        let wasVisible = self.panel.isVisible
        let origin = wasVisible ? self.panel.frame.origin : self.savedOrigin(size: size)
        self.panel.setFrame(CGRect(origin: origin, size: size), display: true)
        self.pillView.frame = CGRect(origin: .zero, size: size)
        self.clampToVisibleScreens()
        if !wasVisible {
            self.panel.orderFrontRegardless()
            self.startRefreshTimer()
        }
        self.panel.invalidateShadow()
    }

    func hide() {
        self.hideHoverPanel()
        self.refreshTimer?.invalidate()
        self.refreshTimer = nil
        self.panel.orderOut(nil)
    }

    func close() {
        if let screenObserver = self.screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        self.hide()
        self.hoverPanel?.close()
        self.hoverPanel = nil
        self.panel.close()
    }

    private func startRefreshTimer() {
        self.refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick?() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.refreshTimer = timer
    }

    // MARK: Position

    private func savedOrigin(size: CGSize) -> CGPoint {
        if let origin = FloatingUsagePillPlacement.storedOrigin(in: self.defaults) { return origin }
        let main = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        return FloatingUsagePillPlacement.defaultOrigin(size: size, mainFrame: main)
    }

    private func saveOrigin() {
        FloatingUsagePillPlacement.store(self.panel.frame.origin, in: self.defaults)
    }

    func clampToVisibleScreens() {
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard let main = NSScreen.main?.visibleFrame ?? frames.first else { return }
        let current = self.panel.frame
        let origin = FloatingUsagePillPlacement.clampedOrigin(
            current.origin, size: current.size, visibleFrames: frames, mainFrame: main)
        if origin != current.origin {
            self.panel.setFrameOrigin(origin)
        }
    }

    // MARK: Hover

    private func hoverChanged() {
        self.hoverShowWork?.cancel()
        self.hoverHideWork?.cancel()
        if self.pointerOnPill || self.pointerOnHoverPanel {
            guard self.hoverPanel?.isVisible != true, self.pointerOnPill, !self.hoverSuppressed else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.showHoverPanel() }
            }
            self.hoverShowWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverShowDelay, execute: work)
        } else {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.hideHoverPanel() }
            }
            self.hoverHideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverHideDelay, execute: work)
        }
    }

    private func showHoverPanel() {
        guard self.pointerOnPill, self.panel.isVisible,
              let content = self.hoverContentProvider?(), !content.models.isEmpty
        else { return }
        let hosting = NSHostingView(rootView: FloatingUsagePillHoverContent(
            models: content.models,
            width: content.width))
        // Cards sit side by side: n card widths plus dividers wide, as tall as the tallest card.
        let size = CGSize(
            width: FloatingUsagePillHoverContent.totalWidth(cardCount: content.models.count, cardWidth: content.width),
            height: hosting.fittingSize.height)
        let container = FloatingUsagePillHoverContainer(frame: CGRect(origin: .zero, size: size))
        // Same backdrop and glass edge as the pill.
        let background = FloatingUsagePillGlass.makeBackground(
            cornerRadius: Self.hoverCornerRadius,
            clear: true,
            strength: .panel)
        background.frame = container.bounds
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        if FloatingUsagePillGlass.isAvailable {
            let rim = FloatingUsagePillRimView(frame: container.bounds)
            rim.cornerRadius = Self.hoverCornerRadius
            rim.wrapsCorners = true
            rim.autoresizingMask = [.width, .height]
            container.addSubview(rim)
        }
        container.onHoverChanged = { [weak self] inside in
            self?.pointerOnHoverPanel = inside
            self?.hoverChanged()
        }
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let hover = self.hoverPanel ?? self.makeHoverPanel()
        hover.contentView = container
        hover.setFrame(CGRect(origin: self.hoverOrigin(size: size), size: size), display: true)
        self.hoverPanel = hover
        self.hoverGeneration += 1
        self.expand(hover, content: container)
    }

    /// Grows the panel out of the pill: it scales up from the pill's centre while it fades in.
    private func expand(_ hover: NSPanel, content: NSView) {
        content.wantsLayer = true
        guard let layer = content.layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            hover.alphaValue = 1
            hover.orderFrontRegardless()
            return
        }
        let grow = CASpringAnimation(keyPath: "transform")
        grow.fromValue = self.pillScaleTransform(for: hover.frame)
        grow.toValue = CATransform3DIdentity
        grow.damping = 22
        grow.stiffness = 260
        grow.duration = grow.settlingDuration
        layer.transform = CATransform3DIdentity
        layer.add(grow, forKey: "expand")

        hover.alphaValue = 0
        hover.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.expandFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hover.animator().alphaValue = 1
        }
    }

    /// Shrinks the panel back into the pill while it fades out, then removes it.
    private func collapse(_ hover: NSPanel) {
        guard let layer = hover.contentView?.layer,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            hover.orderOut(nil)
            return
        }
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = CATransform3DIdentity
        shrink.toValue = self.pillScaleTransform(for: hover.frame)
        shrink.duration = Self.collapseDuration
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        layer.add(shrink, forKey: "expand")
        // A panel shown again while this one closes bumps the generation, so it is not ordered out.
        let generation = self.hoverGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.collapseDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hover.animator().alphaValue = 0
        } completionHandler: { [weak self, weak hover] in
            Task { @MainActor in
                guard let self, let hover, self.hoverGeneration == generation else { return }
                hover.orderOut(nil)
            }
        }
    }

    /// Scales the panel down around the pill's centre, as seen in the panel's own coordinates.
    private func pillScaleTransform(for frame: CGRect) -> CATransform3D {
        let pill = self.panel.frame
        let anchor = CGPoint(
            x: min(frame.width, max(0, pill.midX - frame.minX)),
            y: min(frame.height, max(0, pill.midY - frame.minY)))
        let scale = Self.expandStartScale
        return CATransform3DTranslate(
            CATransform3DScale(CATransform3DMakeTranslation(anchor.x, anchor.y, 0), scale, scale, 1),
            -anchor.x,
            -anchor.y,
            0)
    }

    private func makeHoverPanel() -> NSPanel {
        let hover = FloatingUsagePillPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        hover.level = .floating
        hover.collectionBehavior = [.canJoinAllSpaces]
        hover.isOpaque = false
        hover.backgroundColor = .clear
        hover.hasShadow = !FloatingUsagePillGlass.isAvailable
        hover.hidesOnDeactivate = false
        hover.isReleasedWhenClosed = false
        return hover
    }

    /// Below the pill when it fits, else above. Aligned to the pill's trailing edge and kept on screen.
    private func hoverOrigin(size: CGSize) -> CGPoint {
        let pill = self.panel.frame
        let screen = self.panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? pill
        var y = pill.minY - Self.hoverGap - size.height
        if y < screen.minY { y = pill.maxY + Self.hoverGap }
        var x = pill.maxX - size.width
        x = min(max(x, screen.minX), max(screen.minX, screen.maxX - size.width))
        y = min(max(y, screen.minY), max(screen.minY, screen.maxY - size.height))
        return CGPoint(x: x, y: y)
    }

    func hideHoverPanel() {
        self.hoverShowWork?.cancel()
        self.hoverHideWork?.cancel()
        self.pointerOnHoverPanel = false
        guard let hover = self.hoverPanel, hover.isVisible else { return }
        self.collapse(hover)
    }
}
