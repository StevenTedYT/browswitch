import AppKit
import BrowswitchCore
import os

private let log = Logger(subsystem: AppIdentity.bundleID, category: "routing")

@MainActor
final class LinkRouter {
    static let shared = LinkRouter()

    private let store = Store.shared
    private let browsers = BrowserManager.shared

    func handle(_ url: URL, from source: SourceApp?, forcePicker: Bool = false) {
        let config = store.config
        let force = forcePicker || ModifierKey.areHeld(config.pickerModifiers)

        if !force,
           let rule = Router.firstMatch(for: url, sourceApp: source?.bundleID, in: config.rules),
           let browser = browsers.browser(withID: rule.browser) {
            open(url, in: browser, source: source, reason: .rule(RuleSummary.title(for: rule)))
            return
        }

        if !force, config.fallback == .primary, let browser = browsers.browser(withID: config.primaryBrowser) {
            open(url, in: browser, source: source, reason: .primary)
            return
        }

        log.info("\(url.absoluteString, privacy: .public) from \(source?.bundleID ?? "?", privacy: .public) → picker")
        PickerController.shared.enqueue(url: url, source: source)
    }

    func open(_ url: URL, in browser: Browser, source: SourceApp?, reason: HistoryReason) {
        log.info("\(url.absoluteString, privacy: .public) from \(source?.bundleID ?? "?", privacy: .public) → \(browser.id, privacy: .public) (\(String(describing: reason), privacy: .public))")
        browsers.open(url, in: browser)
        store.record(HistoryEntry(date: Date(), url: url, source: source, browserID: browser.id, reason: reason))
    }

    func recordCancelled(_ url: URL, source: SourceApp?) {
        store.record(HistoryEntry(date: Date(), url: url, source: source, browserID: nil, reason: .cancelled))
    }
}
