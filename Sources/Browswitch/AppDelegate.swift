import AppKit
import BrowswitchCore
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var languageObserver: AnyCancellable?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Registered this early so the link that launched the app is not lost.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BrowserManager.shared.refresh()
        adoptCurrentDefaultAsPrimary()

        languageObserver = Store.shared.$config
            .map(\.language)
            .removeDuplicates()
            .sink { _ in
                // @Published emits before the change is stored.
                DispatchQueue.main.async { NSApp.mainMenu = MainMenu.make() }
            }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Browswitch")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !Store.shared.config.onboarded {
            Store.shared.config.onboarded = true
            SettingsWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// The browser that was the default before Browswitch becomes the primary one.
    private func adoptCurrentDefaultAsPrimary() {
        guard Store.shared.config.primaryBrowser == nil,
              let current = DefaultBrowser.current,
              let id = Bundle(url: current)?.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        Store.shared.config.primaryBrowser = id
    }

    // MARK: - Incoming links

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string)
                ?? string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
        else { return }
        LinkRouter.shared.handle(url, from: Self.sourceApp(of: event))
    }

    /// Local HTML files opened while Browswitch is the default browser.
    func application(_ application: NSApplication, open urls: [URL]) {
        let source = Self.frontmostSource()
        for url in urls { LinkRouter.shared.handle(url, from: source) }
    }

    private static func sourceApp(of event: NSAppleEventDescriptor) -> SourceApp? {
        if let pidDescriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) {
            let pid = pid_t(pidDescriptor.int32Value)
            if pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
               let app = NSRunningApplication(processIdentifier: pid),
               let source = SourceApp(runningApp: app) {
                return source
            }
        }
        return frontmostSource()
    }

    private static func frontmostSource() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return SourceApp(runningApp: app)
    }

    // MARK: - Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !DefaultBrowser.isSelf {
            let item = NSMenuItem(title: L(.menuSetDefault), action: #selector(makeDefault), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let clipboard = NSMenuItem(title: L(.menuOpenClipboard), action: #selector(openClipboardURL), keyEquivalent: "")
        clipboard.target = self
        clipboard.isEnabled = Self.clipboardURL() != nil
        menu.addItem(clipboard)
        menu.addItem(.separator())

        let header = NSMenuItem(title: L(.menuPrimaryBrowser), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let primary = Store.shared.config.primaryBrowser
        for browser in BrowserManager.shared.ordered(includeHidden: false) {
            let item = NSMenuItem(title: browser.name, action: #selector(setPrimary(_:)), keyEquivalent: "")
            item.image = AppInfo.smallIcon(browser.icon)
            item.representedObject = browser.id
            item.state = browser.id.caseInsensitiveCompare(primary ?? "") == .orderedSame ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: L(.menuSettings), action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: L(.menuQuit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func makeDefault() {
        DefaultBrowser.makeSelfDefault {}
    }

    @objc private func setPrimary(_ sender: NSMenuItem) {
        Store.shared.config.primaryBrowser = sender.representedObject as? String
    }

    @objc private func openClipboardURL() {
        guard let url = Self.clipboardURL() else { return }
        LinkRouter.shared.handle(url, from: nil)
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    private static func clipboardURL() -> URL? {
        guard var string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty, !string.contains(" ") else { return nil }
        if string.lowercased().hasPrefix("www.") { string = "https://" + string }
        guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else { return nil }
        return url
    }
}

/// Accessory apps have no menu bar, but text fields still need ⌘C/⌘V/⌘A and windows ⌘W.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L(.menuSettings), action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L(.menuHide), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L(.menuQuit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Browswitch")

        let edit = NSMenu(title: L(.menuEdit))
        edit.addItem(withTitle: L(.menuUndo), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L(.menuRedo), action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L(.menuCut), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L(.menuCopy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L(.menuPaste), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L(.menuSelectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: edit.title)

        let window = NSMenu(title: L(.menuWindow))
        window.addItem(withTitle: L(.menuClose), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: L(.menuMinimize), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: window, title: window.title)

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
