import CodexBarCore
import Foundation

/// Pure description of what the floating usage pill draws. No AppKit.
struct FloatingUsagePillModel: Equatable {
    enum Tone: Equatable {
        case neutral
        case deficit
        case reserve

        init(stage: UsagePace.Stage?, isStale: Bool) {
            guard let stage, !isStale else {
                self = .neutral
                return
            }
            switch stage {
            case .ahead, .farAhead: self = .deficit
            case .behind, .farBehind: self = .reserve
            case .onTrack, .slightlyAhead, .slightlyBehind: self = .neutral
            }
        }
    }

    struct Row: Equatable {
        /// Share of the window that the provider reports as used, 0...1.
        let usedFraction: Double
        /// Share of the window that has already passed, 0...1.
        let elapsedFraction: Double
        /// Share of the bar that is filled. It is the used share, or the remaining share when the menu shows remaining.
        let barFraction: Double
        /// Share of the dashes that is lit. It is the elapsed time, or the remaining time when the menu shows
        /// remaining.
        let dashFraction: Double
        /// Number of time dashes above the usage bar.
        let segmentCount: Int
        let tone: Tone
        let tooltip: String
    }

    struct Column: Equatable {
        let provider: UsageProvider
        /// Session row first, weekly row second. A nil row means the provider reports no such window.
        let rows: [Row?]
        /// One tooltip per row, including rows without a window.
        let tooltips: [String]
    }

    struct Input {
        let provider: UsageProvider
        let session: RateWindow?
        let weekly: RateWindow?
        let sessionStage: UsagePace.Stage?
        let weeklyStage: UsagePace.Stage?
        let isStale: Bool
        /// Set when the session slot holds a model-scoped weekly window (Claude Ultra has no session limit, so the
        /// Fable weekly limit takes its place). The title labels the row, and the row uses weekly timing.
        var sessionTitle: String? = nil
    }

    static let defaultSessionMinutes = 300
    static let defaultWeeklyMinutes = 10080

    let columns: [Column]

    private enum RowKind {
        case session
        case weekly
        /// A weekly-length window shown in the session slot, labeled by its own title.
        case scopedWeekly(title: String)

        private static let sessionMinutes = FloatingUsagePillModel.defaultSessionMinutes
        private static let weeklyMinutes = FloatingUsagePillModel.defaultWeeklyMinutes

        var defaultMinutes: Int {
            if case .session = self { return Self.sessionMinutes }
            return Self.weeklyMinutes
        }

        var segmentCount: Int {
            if case .session = self { return 5 }
            return 7
        }

        func label(_ metadata: ProviderMetadata) -> String {
            switch self {
            case .session: L(metadata.sessionLabel)
            case .weekly: L(metadata.weeklyLabel)
            case let .scopedWeekly(title): title
            }
        }
    }

    /// `showsUsed` mirrors the menu setting: false flips the bar to remaining usage and the dashes to remaining time.
    private struct RowContext {
        let metadata: ProviderMetadata
        let showsUsed: Bool
        let now: Date
    }

    static func make(inputs: [Input], showsUsed: Bool = true, now: Date) -> FloatingUsagePillModel {
        FloatingUsagePillModel(columns: inputs.map { input in
            let metadata = ProviderDescriptorRegistry.descriptor(for: input.provider).metadata
            let context = RowContext(metadata: metadata, showsUsed: showsUsed, now: now)
            let sessionKind: RowKind = input.sessionTitle.map { .scopedWeekly(title: $0) } ?? .session
            let session = self.row(
                window: input.session,
                kind: sessionKind,
                tone: Tone(stage: input.sessionStage, isStale: input.isStale),
                context: context)
            let weekly = self.row(
                window: input.weekly,
                kind: .weekly,
                tone: Tone(stage: input.weeklyStage, isStale: input.isStale),
                context: context)
            return Column(
                provider: input.provider,
                rows: [session, weekly],
                tooltips: [
                    session?.tooltip
                        ?? L("floating_pill_row_empty_tooltip", metadata.displayName, sessionKind.label(metadata)),
                    weekly?.tooltip
                        ?? L("floating_pill_row_empty_tooltip", metadata.displayName, RowKind.weekly.label(metadata)),
                ])
        })
    }

    static func usedFraction(_ usedPercent: Double) -> Double {
        guard usedPercent.isFinite else { return 0 }
        return min(1, max(0, usedPercent / 100))
    }

    static func elapsedFraction(window: RateWindow, defaultMinutes: Int, now: Date) -> Double {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return 0 }
        let total = TimeInterval((window.windowMinutes ?? defaultMinutes) * 60)
        guard total > 0 else { return 0 }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(1, max(0, 1 - remaining / total))
    }

    /// Share of the window that is left. Zero when the reset time is unknown or already past, like `elapsedFraction`.
    static func remainingFraction(window: RateWindow, defaultMinutes: Int, now: Date) -> Double {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return 0 }
        return 1 - self.elapsedFraction(window: window, defaultMinutes: defaultMinutes, now: now)
    }

    private static func row(
        window: RateWindow?,
        kind: RowKind,
        tone: Tone,
        context: RowContext) -> Row?
    {
        guard let window else { return nil }
        let (metadata, showsUsed, now) = (context.metadata, context.showsUsed, context.now)
        let used = self.usedFraction(window.usedPercent)
        let elapsed = self.elapsedFraction(window: window, defaultMinutes: kind.defaultMinutes, now: now)
        let remaining = self.remainingFraction(window: window, defaultMinutes: kind.defaultMinutes, now: now)
        return Row(
            usedFraction: used,
            elapsedFraction: elapsed,
            barFraction: showsUsed ? used : 1 - used,
            dashFraction: showsUsed ? elapsed : remaining,
            segmentCount: kind.segmentCount,
            tone: tone,
            tooltip: L(
                "floating_pill_row_tooltip",
                metadata.displayName,
                kind.label(metadata),
                Int((used * 100).rounded())))
    }
}
