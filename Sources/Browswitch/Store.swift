import AppKit
import BrowswitchCore

enum HistoryReason: Codable, Equatable {
    case rule(String)
    case primary
    case manual
    case remembered(String)
    case cancelled

    @MainActor var text: String {
        switch self {
        case .rule(let name): return L(.reasonRule, name)
        case .primary: return L(.reasonPrimary)
        case .manual: return L(.reasonManual)
        case .remembered(let domain): return L(.reasonRemembered, domain)
        case .cancelled: return L(.reasonCancelled)
        }
    }
}

struct HistoryEntry: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let url: URL
    let source: SourceApp?
    /// nil when the picker was dismissed.
    let browserID: String?
    let reason: HistoryReason
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    private static let historyLimit = 100

    @Published var config: Config {
        didSet { if config != oldValue { save() } }
    }

    @Published private(set) var history: [HistoryEntry] = []

    let fileURL: URL
    private let historyURL: URL

    private init() {
        if let override = ProcessInfo.processInfo.environment["BROWSWITCH_CONFIG"] {
            fileURL = URL(fileURLWithPath: override)
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Browswitch", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("config.json")
        }
        historyURL = fileURL.deletingLastPathComponent().appendingPathComponent("history.json")

        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(Config.self, from: data) {
                config = decoded
            } else {
                // Keep an unreadable (e.g. badly hand-edited) file instead of overwriting it on the next save.
                let backup = fileURL.deletingPathExtension().appendingPathExtension("invalid.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
                NSLog("Browswitch: unreadable config, kept a copy at \(backup.path)")
                config = Config()
            }
        } else {
            config = Config()
        }

        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = decoded
        }
    }

    private func save() {
        write(config, to: fileURL, pretty: true)
    }

    private func write<T: Encodable>(_ value: T, to url: URL, pretty: Bool) {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        do {
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("Browswitch: cannot write \(url.lastPathComponent): \(error)")
        }
    }

    func record(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        write(history, to: historyURL, pretty: false)
    }

    func clearHistory() {
        history = []
        try? FileManager.default.removeItem(at: historyURL)
    }

    func rememberDomain(_ domain: String, browser: String) {
        if let index = config.rules.firstIndex(where: {
            !$0.hasSourceCondition && $0.matchKind == .domain && Router.domainPatterns($0.pattern) == [domain]
        }) {
            config.rules[index].browser = browser
            config.rules[index].enabled = true
        } else {
            config.rules.append(Rule(name: domain, matchKind: .domain, pattern: domain, browser: browser))
        }
    }
}
