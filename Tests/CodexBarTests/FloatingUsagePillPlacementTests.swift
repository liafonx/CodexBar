import CoreGraphics
import Foundation
import Testing
@testable import CodexBar

struct FloatingUsagePillPlacementTests {
    private let size = CGSize(width: 80, height: 34)
    private let main = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let side = CGRect(x: 1000, y: 0, width: 600, height: 800)

    @Test
    func `origin inside the frame is kept`() {
        let origin = FloatingUsagePillPlacement.clampedOrigin(
            CGPoint(x: 300, y: 400), size: self.size, visibleFrames: [self.main], mainFrame: self.main)
        #expect(origin == CGPoint(x: 300, y: 400))
    }

    @Test
    func `off screen origin moves onto the main frame`() {
        let origin = FloatingUsagePillPlacement.clampedOrigin(
            CGPoint(x: 5000, y: 5000), size: self.size, visibleFrames: [self.main], mainFrame: self.main)
        #expect(origin == CGPoint(x: 920, y: 766))
    }

    @Test
    func `edge overflow is clamped`() {
        let origin = FloatingUsagePillPlacement.clampedOrigin(
            CGPoint(x: 960, y: -10), size: self.size, visibleFrames: [self.main], mainFrame: self.main)
        #expect(origin == CGPoint(x: 920, y: 0))
    }

    @Test
    func `pill on a second screen stays there`() {
        let origin = FloatingUsagePillPlacement.clampedOrigin(
            CGPoint(x: 1550, y: 100), size: self.size, visibleFrames: [self.main, self.side], mainFrame: self.main)
        #expect(origin == CGPoint(x: 1520, y: 100))
    }

    @Test
    func `removed screen sends the pill to the main frame`() {
        let origin = FloatingUsagePillPlacement.clampedOrigin(
            CGPoint(x: 1200, y: 100), size: self.size, visibleFrames: [self.main], mainFrame: self.main)
        #expect(origin == CGPoint(x: 920, y: 100))
    }

    @Test
    func `default origin is top right with the inset`() {
        let origin = FloatingUsagePillPlacement.defaultOrigin(size: self.size, mainFrame: self.main)
        #expect(origin == CGPoint(x: 904, y: 750))
    }

    @Test
    func `stored origin round trips including zero`() {
        let defaults = InMemoryUserDefaults()
        #expect(FloatingUsagePillPlacement.storedOrigin(in: defaults) == nil)
        FloatingUsagePillPlacement.store(.zero, in: defaults)
        #expect(FloatingUsagePillPlacement.storedOrigin(in: defaults) == .zero)
        FloatingUsagePillPlacement.store(CGPoint(x: 12.5, y: -30), in: defaults)
        #expect(FloatingUsagePillPlacement.storedOrigin(in: defaults) == CGPoint(x: 12.5, y: -30))
    }

    @Test
    func `undecodable stored origin is treated as missing`() {
        let defaults = InMemoryUserDefaults()
        defaults.set("garbage", forKey: FloatingUsagePillPlacement.originDefaultsKey)
        #expect(FloatingUsagePillPlacement.storedOrigin(in: defaults) == nil)
        defaults.set([1.0], forKey: FloatingUsagePillPlacement.originDefaultsKey)
        #expect(FloatingUsagePillPlacement.storedOrigin(in: defaults) == nil)
    }
}
