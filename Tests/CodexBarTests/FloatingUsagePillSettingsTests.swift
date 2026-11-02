import Foundation
import Testing
@testable import CodexBar

@MainActor
struct FloatingUsagePillSettingsTests {
    @Test
    func `floating pill defaults off and persists`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: "floating-pill-defaults", userDefaults: defaults)
        #expect(!settings.floatingUsagePillEnabled)
        #expect(defaults.object(forKey: "floatingUsagePillEnabled") == nil)
        settings.floatingUsagePillEnabled = true
        #expect(testSettingsStore(suiteName: "floating-pill-reloaded", userDefaults: defaults)
            .floatingUsagePillEnabled)
        settings.floatingUsagePillEnabled = false
        #expect(!testSettingsStore(suiteName: "floating-pill-reloaded-off", userDefaults: defaults)
            .floatingUsagePillEnabled)
    }
}
