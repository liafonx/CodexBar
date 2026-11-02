import AppKit
import CodexBarCore
import Observation

// MARK: - Floating usage pill glue

extension StatusItemController {
    private static let floatingPillProviders: [UsageProvider] = [.codex, .claude]

    /// Starts the pill's own observation. It does not use the menu observation token, which rebuilds menus.
    func startFloatingUsagePill() {
        self.observeFloatingUsagePill()
        self.refreshFloatingUsagePill()
    }

    private func observeFloatingUsagePill() {
        withObservationTracking {
            _ = self.settings.floatingUsagePillEnabled
            _ = self.settings.usageBarsShowUsed
            if self.settings.floatingUsagePillEnabled {
                _ = self.floatingUsagePillModel(now: Date())
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.hasPreparedForAppShutdown else { return }
                self.observeFloatingUsagePill()
                self.refreshFloatingUsagePill()
            }
        }
    }

    func refreshFloatingUsagePill() {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        guard !self.hasPreparedForAppShutdown else { return }
        guard self.settings.floatingUsagePillEnabled else {
            self.floatingUsagePill?.hide()
            return
        }
        let model = self.floatingUsagePillModel(now: Date())
        guard !model.columns.isEmpty else {
            self.floatingUsagePill?.hide()
            return
        }
        self.ensureFloatingUsagePill().show(model: model)
    }

    private func ensureFloatingUsagePill() -> FloatingUsagePillController {
        if let existing = self.floatingUsagePill { return existing }
        let pill = FloatingUsagePillController(defaults: self.settings.userDefaults)
        pill.onClick = { [weak self] in self?.openMenuFromFloatingPill() }
        pill.onRightClick = { [weak self] in self?.openAppMenuFromFloatingPill() }
        pill.onTick = { [weak self] in self?.refreshFloatingUsagePill() }
        pill.hoverContentProvider = { [weak self] in self?.floatingUsagePillHoverContent() ?? ([], 0) }
        self.floatingUsagePill = pill
        return pill
    }

    func floatingUsagePillModel(now: Date) -> FloatingUsagePillModel {
        let inputs = Self.floatingPillProviders.filter { self.store.isEnabled($0) }.map { provider in
            self.floatingUsagePillInput(for: provider, now: now)
        }
        return FloatingUsagePillModel.make(inputs: inputs, showsUsed: self.settings.usageBarsShowUsed, now: now)
    }

    private func floatingUsagePillInput(for provider: UsageProvider, now: Date) -> FloatingUsagePillModel.Input {
        let snapshot = self.store.presentationSnapshot(for: provider)
        // Semantic windows follow window length and skip synthetic placeholders; never read slots directly.
        let windows = snapshot.map {
            ProviderDescriptorRegistry.descriptor(for: provider).presentation.semanticWindows(snapshot: $0)
        }
        let sessionStage = windows?.session.flatMap {
            UsagePaceText.sessionPace(provider: provider, window: $0, now: now)?.stage
        }
        let weeklyStage = windows?.weekly.flatMap {
            self.store.weeklyPace(
                provider: provider,
                window: $0,
                dataConfidence: snapshot?.dataConfidence ?? .unknown,
                now: now)?.stage
        }
        return FloatingUsagePillModel.Input(
            provider: provider,
            session: windows?.session,
            weekly: windows?.weekly,
            sessionStage: sessionStage,
            weeklyStage: weeklyStage,
            isStale: self.store.errors[provider.instanceID] != nil)
    }

    private func floatingUsagePillHoverContent() -> (models: [UsageMenuCardView.Model], width: CGFloat) {
        let providers = Self.floatingPillProviders.filter { self.store.isEnabled($0) }
        let models = providers.compactMap { self.menuCardModel(for: $0) }
        let width = providers.map { provider in
            self.menuCardWidth(
                for: providers,
                selectedProvider: provider,
                descriptor: self.makeMenuDescriptor(provider: provider, includeContextualActions: false))
        }.max() ?? Self.menuCardBaseWidth
        return (models, width)
    }

    /// Opens the menu that the global shortcut would open, anchored to the pill.
    func openMenuFromFloatingPill() {
        guard let pill = self.floatingUsagePill else { return }
        // Shared by click and shortcut: drop the hover card and any pending show before the menu tracks.
        pill.hideHoverPanel()
        let anchor = pill.anchorView
        if self.closeOpenMenusFromShortcutIfNeeded() { return }
        let menu: NSMenu? = if self.shouldMergeIcons {
            self.mergedMenu ?? self.statusItem.menu
        } else {
            self.lazyStatusItem(for: self.resolvedShortcutProvider()).menu
        }
        guard let menu else { return }
        // The controller is the menu delegate, so menuWillOpen runs exactly as for a status item click.
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
    }

    /// Right click: only the app actions from the bottom of the main menu.
    func openAppMenuFromFloatingPill() {
        guard let pill = self.floatingUsagePill else { return }
        pill.hideHoverPanel()
        let versionText = AppVersion.shortVersion
        let aboutTitle = L("About CodexBar") + (versionText.isEmpty ? "" : " (v\(versionText))")
        let entries: [(String, MenuDescriptor.MenuAction)] = [
            (L("Refresh"), .refresh),
            (L("Settings..."), .settings),
            (aboutTitle, .about),
            (L("Quit"), .quit),
        ]
        let menu = NSMenu()
        for (title, action) in entries {
            let (selector, represented) = self.selector(for: action)
            let shortcut = self.shortcut(for: action)
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: shortcut?.key ?? "")
            item.keyEquivalentModifierMask = shortcut?.modifiers ?? []
            item.target = self
            item.representedObject = represented
            menu.addItem(item)
        }
        let anchor = pill.anchorView
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
    }

    var isFloatingUsagePillVisible: Bool {
        self.floatingUsagePill?.isVisible == true
    }

    func closeFloatingUsagePill() {
        self.floatingUsagePill?.close()
        self.floatingUsagePill = nil
    }
}
