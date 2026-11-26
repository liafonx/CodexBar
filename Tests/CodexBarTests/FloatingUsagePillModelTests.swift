import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct FloatingUsagePillModelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(
        used: Double,
        minutes: Int?,
        resetsIn seconds: TimeInterval?,
        placeholder: Bool = false) -> RateWindow
    {
        RateWindow(
            usedPercent: used,
            windowMinutes: minutes,
            resetsAt: seconds.map { self.now.addingTimeInterval($0) },
            resetDescription: nil,
            isSyntheticPlaceholder: placeholder)
    }

    private func input(
        provider: UsageProvider = .codex,
        session: RateWindow? = nil,
        weekly: RateWindow? = nil,
        sessionStage: UsagePace.Stage? = nil,
        weeklyStage: UsagePace.Stage? = nil,
        isStale: Bool = false) -> FloatingUsagePillModel.Input
    {
        FloatingUsagePillModel.Input(
            provider: provider,
            session: session,
            weekly: weekly,
            sessionStage: sessionStage,
            weeklyStage: weeklyStage,
            isStale: isStale)
    }

    private func firstRow(
        _ input: FloatingUsagePillModel.Input,
        showsUsed: Bool = true) throws -> FloatingUsagePillModel.Row
    {
        let model = FloatingUsagePillModel.make(inputs: [input], showsUsed: showsUsed, now: self.now)
        return try #require(model.columns.first?.rows[0])
    }

    @Test
    func `semantic windows drop the Claude synthetic placeholder session`() throws {
        let snapshot = UsageSnapshot(
            primary: self.window(used: 0, minutes: 300, resetsIn: nil, placeholder: true),
            secondary: self.window(used: 40, minutes: 10080, resetsIn: 86400),
            updatedAt: self.now)
        let windows = ProviderDescriptorRegistry.descriptor(for: .claude).presentation
            .semanticWindows(snapshot: snapshot)
        #expect(windows.session == nil)
        let model = FloatingUsagePillModel.make(
            inputs: [self.input(provider: .claude, session: windows.session, weekly: windows.weekly)],
            now: self.now)
        let rows = try #require(model.columns.first?.rows)
        #expect(rows[0] == nil)
        #expect(rows[1]?.usedFraction == 0.4)
    }

    @Test
    func `semantic windows follow duration when Codex slots are swapped`() throws {
        let weekly = self.window(used: 30, minutes: 10080, resetsIn: 86400)
        let session = self.window(used: 70, minutes: 300, resetsIn: 3600)
        let snapshot = UsageSnapshot(primary: weekly, secondary: session, updatedAt: self.now)
        let windows = ProviderDescriptorRegistry.descriptor(for: .codex).presentation
            .semanticWindows(snapshot: snapshot)
        #expect(windows.session == session)
        #expect(windows.weekly == weekly)
        let model = FloatingUsagePillModel.make(
            inputs: [self.input(session: windows.session, weekly: windows.weekly)],
            now: self.now)
        let rows = try #require(model.columns.first?.rows)
        #expect(rows[0]?.usedFraction == 0.7)
        #expect(rows[1]?.usedFraction == 0.3)
    }

    @Test
    func `stage maps to tone`() {
        typealias Tone = FloatingUsagePillModel.Tone
        #expect(Tone(stage: .ahead, isStale: false) == .deficit)
        #expect(Tone(stage: .farAhead, isStale: false) == .deficit)
        #expect(Tone(stage: .behind, isStale: false) == .reserve)
        #expect(Tone(stage: .farBehind, isStale: false) == .reserve)
        #expect(Tone(stage: .onTrack, isStale: false) == .neutral)
        #expect(Tone(stage: .slightlyAhead, isStale: false) == .neutral)
        #expect(Tone(stage: .slightlyBehind, isStale: false) == .neutral)
        #expect(Tone(stage: nil, isStale: false) == .neutral)
    }

    @Test
    func `stale provider gets neutral dashes`() throws {
        let row = try self.firstRow(self.input(
            session: self.window(used: 10, minutes: 300, resetsIn: 3600),
            sessionStage: .farAhead,
            isStale: true))
        #expect(row.tone == .neutral)
    }

    @Test
    func `elapsed fraction covers mid window just reset nil reset and past reset`() {
        func elapsed(_ window: RateWindow) -> Double {
            FloatingUsagePillModel.elapsedFraction(window: window, defaultMinutes: 300, now: self.now)
        }
        #expect(elapsed(self.window(used: 0, minutes: 300, resetsIn: 150 * 60)) == 0.5)
        #expect(elapsed(self.window(used: 0, minutes: 300, resetsIn: 300 * 60)) == 0)
        #expect(elapsed(self.window(used: 0, minutes: 300, resetsIn: nil)) == 0)
        #expect(elapsed(self.window(used: 0, minutes: 300, resetsIn: -60)) == 0)
        #expect(elapsed(self.window(used: 0, minutes: 300, resetsIn: 400 * 60)) == 0)
        // A missing window length falls back to the default for the row.
        #expect(elapsed(self.window(used: 0, minutes: nil, resetsIn: 75 * 60)) == 0.75)
    }

    @Test
    func `used fraction is clamped`() {
        #expect(FloatingUsagePillModel.usedFraction(0) == 0)
        #expect(FloatingUsagePillModel.usedFraction(100) == 1)
        #expect(FloatingUsagePillModel.usedFraction(140) == 1)
        #expect(FloatingUsagePillModel.usedFraction(-5) == 0)
        #expect(FloatingUsagePillModel.usedFraction(25) == 0.25)
    }

    @Test
    func `missing window gives a nil row and an empty tooltip`() {
        let model = FloatingUsagePillModel.make(
            inputs: [self.input(weekly: self.window(used: 10, minutes: 10080, resetsIn: 3600))],
            now: self.now)
        let column = model.columns[0]
        #expect(column.rows[0] == nil)
        #expect(column.rows[1] != nil)
        #expect(column.tooltips.count == 2)
        #expect(!column.tooltips[0].isEmpty)
    }

    @Test
    func `one provider gives one column and two give two`() {
        let codex = self.input(provider: .codex)
        let claude = self.input(provider: .claude)
        #expect(FloatingUsagePillModel.make(inputs: [codex], now: self.now).columns.map(\.provider) == [.codex])
        #expect(FloatingUsagePillModel.make(inputs: [codex, claude], now: self.now).columns
            .map(\.provider) == [.codex, .claude])
        #expect(FloatingUsagePillModel.make(inputs: [], now: self.now).columns.isEmpty)
    }

    @Test
    func `segment counts are five for session and seven for weekly`() {
        let model = FloatingUsagePillModel.make(
            inputs: [self.input(
                session: self.window(used: 1, minutes: 300, resetsIn: 60),
                weekly: self.window(used: 1, minutes: 10080, resetsIn: 60))],
            now: self.now)
        #expect(model.columns[0].rows.map { $0?.segmentCount } == [5, 7])
    }

    @Test
    func `tooltip names the provider and the used percent`() throws {
        let row = try self.firstRow(self.input(session: self.window(used: 42.4, minutes: 300, resetsIn: 3600)))
        #expect(row.tooltip.contains("Codex"))
        #expect(row.tooltip.contains("42"))
    }

    @Test
    func `tooltip localizes the window label and the format`() throws {
        let row = try CodexBarLocalizationOverride.$appLanguage.withValue("de") {
            try self.firstRow(self.input(session: self.window(used: 42, minutes: 300, resetsIn: 3600)))
        }
        #expect(row.tooltip == "Codex Sitzung: 42% verbraucht")
    }

    @Test
    func `showing used fills the bar with used and lights elapsed time`() throws {
        let row = try self.firstRow(
            self.input(session: self.window(used: 30, minutes: 300, resetsIn: 75 * 60)),
            showsUsed: true)
        #expect(row.barFraction == 0.3)
        #expect(row.dashFraction == 0.75)
    }

    @Test
    func `showing remaining fills the bar with remaining and lights remaining time`() throws {
        let row = try self.firstRow(
            self.input(session: self.window(used: 30, minutes: 300, resetsIn: 75 * 60)),
            showsUsed: false)
        #expect(row.barFraction == 0.7)
        #expect(row.dashFraction == 0.25)
        // The raw fractions and the tone do not depend on the setting.
        #expect(row.usedFraction == 0.3)
        #expect(row.elapsedFraction == 0.75)
    }

    @Test
    func `showing remaining keeps tone and leaves dashes dark without a reset time`() throws {
        let row = try self.firstRow(
            self.input(session: self.window(used: 100, minutes: 300, resetsIn: nil), sessionStage: .farAhead),
            showsUsed: false)
        #expect(row.barFraction == 0)
        #expect(row.dashFraction == 0)
        #expect(row.tone == .deficit)
    }

    @Test
    func `remaining fraction mirrors elapsed fraction`() {
        func remaining(_ window: RateWindow) -> Double {
            FloatingUsagePillModel.remainingFraction(window: window, defaultMinutes: 300, now: self.now)
        }
        #expect(remaining(self.window(used: 0, minutes: 300, resetsIn: 150 * 60)) == 0.5)
        #expect(remaining(self.window(used: 0, minutes: 300, resetsIn: 300 * 60)) == 1)
        #expect(remaining(self.window(used: 0, minutes: 300, resetsIn: nil)) == 0)
        #expect(remaining(self.window(used: 0, minutes: 300, resetsIn: -60)) == 0)
    }

    @Test
    func `used-up window counts down to its reset in either bar mode`() throws {
        for showsUsed in [true, false] {
            let row = try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
                try self.firstRow(
                    self.input(session: self.window(used: 100, minutes: 300, resetsIn: 2 * 3600 + 5 * 60)),
                    showsUsed: showsUsed)
            }
            #expect(row.resetCountdown == ["2h 5m", "2h"])
        }
    }

    @Test
    func `window with usage left or no future reset shows no countdown`() throws {
        let partial = try self.firstRow(self.input(session: self.window(used: 99.9, minutes: 300, resetsIn: 3600)))
        let over = try self.firstRow(self.input(session: self.window(used: 101, minutes: 300, resetsIn: 3600)))
        let unknown = try self.firstRow(self.input(session: self.window(used: 100, minutes: 300, resetsIn: nil)))
        let past = try self.firstRow(self.input(session: self.window(used: 100, minutes: 300, resetsIn: -60)))
        #expect(partial.resetCountdown == nil)
        #expect(over.resetCountdown != nil)
        #expect(unknown.resetCountdown == nil)
        #expect(past.resetCountdown == nil)
    }

    @Test
    func `countdown offers two units then the largest unit alone`() {
        func texts(_ seconds: TimeInterval) -> [String]? {
            CodexBarLocalizationOverride.$appLanguage.withValue("en") {
                FloatingUsagePillModel.countdownTexts(until: self.now.addingTimeInterval(seconds), now: self.now)
            }
        }
        #expect(texts(3 * 86400 + 4 * 3600 + 30) == ["3d 4h", "3d"])
        #expect(texts(3 * 86400 + 20 * 60) == ["3d"])
        #expect(texts(5 * 3600) == ["5h"])
        #expect(texts(59 * 60 + 1) == ["1h"])
        #expect(texts(42 * 60) == ["42m"])
        #expect(texts(10) == ["1m"])
        #expect(texts(0) == nil)
    }

    @Test
    func `scoped weekly session slot uses weekly timing and its own title`() throws {
        var input = self.input(
            provider: .claude,
            session: self.window(used: 30, minutes: nil, resetsIn: 7 * 86400 / 2))
        input.sessionTitle = "Fable only"
        let model = FloatingUsagePillModel.make(inputs: [input], now: self.now)
        let column = try #require(model.columns.first)
        let row = try #require(column.rows[0])
        #expect(row.segmentCount == 7)
        #expect(abs(row.elapsedFraction - 0.5) < 0.0001)
        #expect(row.tooltip.contains("Fable only"))
        #expect(column.tooltips[1].contains("Claude"))
    }

    private func claudeSnapshot(loginMethod: String?) -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: self.window(used: 40, minutes: 10080, resetsIn: 86400),
            extraRateWindows: [
                NamedRateWindow(
                    id: "claude-weekly-scoped-fable",
                    title: "Fable only",
                    window: self.window(used: 25, minutes: 10080, resetsIn: 86400)),
            ],
            updatedAt: self.now,
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: loginMethod))
    }

    @Test
    func `Claude without a session limit swaps the session slot for the Fable weekly limit`() {
        let snapshot = self.claudeSnapshot(loginMethod: "Claude Max")
        let swapped = StatusItemController.scopedWeeklyInPlaceOfSession(
            provider: .claude, session: nil, snapshot: snapshot)
        #expect(swapped?.title == "Fable only")
        #expect(StatusItemController.scopedWeeklyInPlaceOfSession(
            provider: .claude,
            session: self.window(used: 10, minutes: 300, resetsIn: 3600),
            snapshot: snapshot) == nil)
        #expect(StatusItemController.scopedWeeklyInPlaceOfSession(
            provider: .codex, session: nil, snapshot: snapshot) == nil)
    }

    @Test
    func `hover cards sit in one row with dividers`() {
        #expect(FloatingUsagePillHoverContent.totalWidth(cardCount: 1, cardWidth: 310) == 310)
        #expect(FloatingUsagePillHoverContent.totalWidth(cardCount: 2, cardWidth: 310) == 621)
    }

    @Test
    func `pill is a capsule concentric with the rings`() {
        #expect(FloatingUsagePillLayout.height == 66)
        #expect(FloatingUsagePillLayout.cornerRadius == FloatingUsagePillLayout.height / 2)
        #expect(FloatingUsagePillLayout.cornerRadius
            == FloatingUsagePillLayout.ringDiameter / 2 + FloatingUsagePillLayout.sidePadding)
        #expect(FloatingUsagePillLayout.size(columnCount: 2) == CGSize(width: 128, height: 66))
        #expect(FloatingUsagePillLayout.size(columnCount: 1) == CGSize(width: 66, height: 66))
    }
}
