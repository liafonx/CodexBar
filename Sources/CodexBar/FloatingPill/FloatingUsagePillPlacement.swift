import CoreGraphics
import Foundation

/// Pure placement rules for the floating usage pill. Frames use AppKit screen coordinates (origin bottom-left).
enum FloatingUsagePillPlacement {
    static let edgeInset: CGFloat = 16

    /// Top-right corner of the main visible frame, inset from the edges.
    static func defaultOrigin(size: CGSize, mainFrame: CGRect) -> CGPoint {
        CGPoint(
            x: mainFrame.maxX - size.width - self.edgeInset,
            y: mainFrame.maxY - size.height - self.edgeInset)
    }

    /// Keeps the pill on a visible screen. The screen that holds the pill's center wins, else the main frame.
    static func clampedOrigin(
        _ origin: CGPoint,
        size: CGSize,
        visibleFrames: [CGRect],
        mainFrame: CGRect) -> CGPoint
    {
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let frame = visibleFrames.first { $0.contains(center) } ?? mainFrame
        let maxX = max(frame.minX, frame.maxX - size.width)
        let maxY = max(frame.minY, frame.maxY - size.height)
        return CGPoint(
            x: min(max(origin.x, frame.minX), maxX),
            y: min(max(origin.y, frame.minY), maxY))
    }

    // MARK: Persistence

    static let originDefaultsKey = "floatingUsagePillOrigin"

    /// The saved origin, or nil when nothing usable is stored. An origin of {0, 0} is valid.
    static func storedOrigin(in defaults: UserDefaults) -> CGPoint? {
        guard let values = defaults.array(forKey: self.originDefaultsKey) as? [Double],
              values.count == 2,
              values.allSatisfy(\.isFinite)
        else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    static func store(_ origin: CGPoint, in defaults: UserDefaults) {
        defaults.set([Double(origin.x), Double(origin.y)], forKey: self.originDefaultsKey)
    }
}
