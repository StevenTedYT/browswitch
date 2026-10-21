import AppKit
import UniformTypeIdentifiers

/// An installed app that can open web links.
struct Browser: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// The app a link was clicked in.
struct SourceApp: Hashable, Codable {
    let bundleID: String
    let name: String
    let url: URL?

    var icon: NSImage {
        url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
    }

    init(bundleID: String, name: String? = nil, url: URL? = nil) {
        let resolvedURL = url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        self.bundleID = bundleID
        self.url = resolvedURL
        self.name = name ?? resolvedURL.map(AppInfo.displayName(of:)) ?? bundleID
    }

    /// Resolves helper processes (e.g. "Discord Helper.app" nested in Discord.app) to their enclosing app.
    init?(runningApp: NSRunningApplication) {
        guard var bundleURL = runningApp.bundleURL else {
            guard let id = runningApp.bundleIdentifier else { return nil }
            self.init(bundleID: id, name: runningApp.localizedName)
            return
        }
        let components = bundleURL.pathComponents
        if let outermost = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            bundleURL = URL(fileURLWithPath: NSString.path(withComponents: Array(components[...outermost])))
        }
        guard let id = Bundle(url: bundleURL)?.bundleIdentifier ?? runningApp.bundleIdentifier else { return nil }
        self.init(bundleID: id, url: bundleURL)
    }

    // Stored in the history; the app's location is looked up again when loading.
    private enum CodingKeys: String, CodingKey { case bundleID, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bundleID: try c.decode(String.self, forKey: .bundleID), name: try c.decodeIfPresent(String.self, forKey: .name))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(name, forKey: .name)
    }
}

enum AppIdentity {
    /// Falls back for unbundled debug builds, which have no Info.plist.
    static let bundleID = Bundle.main.bundleIdentifier ?? "app.browswitch.Browswitch"
}

enum AppInfo {
    static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Icon sized for menus and pickers, which otherwise draw NSImages at full size.
    static func smallIcon(_ image: NSImage, size: CGFloat = 16) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: size, height: size)
        return copy
    }
}

@MainActor
final class BrowserManager: ObservableObject {
    static let shared = BrowserManager()

    @Published private(set) var installed: [Browser] = []

    func refresh() {
        let probe = URL(string: "https://example.com")!
        // Apps like downloaders also claim https links; real browsers open HTML files too.
        let htmlViewers = Set(NSWorkspace.shared.urlsForApplications(toOpen: UTType.html).map(\.standardizedFileURL))
        let ownID = AppIdentity.bundleID.lowercased()
        var byID: [String: Browser] = [:]
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
            guard htmlViewers.contains(appURL.standardizedFileURL),
                  let id = Bundle(url: appURL)?.bundleIdentifier else { continue }
            let key = id.lowercased()
            if key == ownID { continue }
            // Several copies of the same app can be registered; prefer the one in /Applications.
            if let existing = byID[key], existing.url.path.hasPrefix("/Applications/") { continue }
            byID[key] = Browser(id: id, name: AppInfo.displayName(of: appURL), url: appURL)
        }
        installed = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func ordered(includeHidden: Bool) -> [Browser] {
        if installed.isEmpty { refresh() }
        let config = Store.shared.config
        let order = config.browserOrder.map { $0.lowercased() }
        let hidden = Set(config.hiddenBrowsers.map { $0.lowercased() })
        return installed
            .filter { includeHidden || !hidden.contains($0.id.lowercased()) }
            .sorted { a, b in
                let ia = order.firstIndex(of: a.id.lowercased()) ?? Int.max
                let ib = order.firstIndex(of: b.id.lowercased()) ?? Int.max
                if ia != ib { return ia < ib }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    func browser(withID id: String?) -> Browser? {
        guard let id, !id.isEmpty else { return nil }
        if installed.isEmpty { refresh() }
        if let browser = installed.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) { return browser }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return Browser(id: id, name: AppInfo.displayName(of: url), url: url)
    }

    func open(_ url: URL, in browser: Browser) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: browser.url, configuration: configuration) { _, error in
            if let error { NSLog("Browswitch: cannot open \(url) in \(browser.name): \(error)") }
        }
    }
}

@MainActor
enum KnownApps {
    /// Apps offered as link sources in the rule editor: running apps, plus those seen in history or rules.
    static func list() -> [SourceApp] {
        var byID: [String: SourceApp] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let source = SourceApp(runningApp: app) { byID[source.bundleID.lowercased()] = source }
        }
        for entry in Store.shared.history {
            if let source = entry.source { byID[source.bundleID.lowercased()] = source }
        }
        for rule in Store.shared.config.rules {
            if let id = rule.sourceApp, !id.isEmpty, byID[id.lowercased()] == nil {
                byID[id.lowercased()] = SourceApp(bundleID: id)
            }
        }
        if let ownID = Bundle.main.bundleIdentifier { byID[ownID.lowercased()] = nil }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
enum DefaultBrowser {
    static var current: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
    }

    static var isSelf: Bool {
        guard let current else { return false }
        return Bundle(url: current)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS asks the user to confirm the change.
    static func makeSelfDefault(completion: @escaping () -> Void) {
        let app = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { _ in
            DispatchQueue.main.async {
                if isSelf { completion(); return }
                NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https") { _ in
                    DispatchQueue.main.async(execute: completion)
                }
            }
        }
    }
}
