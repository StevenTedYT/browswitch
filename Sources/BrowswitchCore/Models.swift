import Foundation

public enum MatchKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case domain
    case contains
    case regex

    public var id: String { rawValue }
}

/// Modifier keys that, held while clicking a link, force the picker. Declared in Apple's display order.
public enum ModifierKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case control, option, shift, command

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }
}

public struct Rule: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    /// Bundle identifier of the app the link comes from. nil = any app.
    public var sourceApp: String?
    public var matchKind: MatchKind
    /// Empty = any URL.
    public var pattern: String
    public var browser: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        enabled: Bool = true,
        sourceApp: String? = nil,
        matchKind: MatchKind = .domain,
        pattern: String = "",
        browser: String = ""
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.sourceApp = sourceApp
        self.matchKind = matchKind
        self.pattern = pattern
        self.browser = browser
    }

    public var hasSourceCondition: Bool { !(sourceApp ?? "").isEmpty }

    public var hasURLCondition: Bool { !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if hasURLCondition { return pattern }
        return sourceApp ?? ""
    }
}

/// What to do when no rule matches a link.
public enum Fallback: String, Codable, CaseIterable, Identifiable, Sendable {
    case ask
    case primary

    public var id: String { rawValue }
}

public struct Config: Codable, Equatable, Sendable {
    public var rules: [Rule]
    public var fallback: Fallback
    public var primaryBrowser: String?
    public var hiddenBrowsers: [String]
    public var browserOrder: [String]
    public var onboarded: Bool
    public var language: Language
    /// Empty = no shortcut.
    public var pickerModifiers: [ModifierKey]

    public init(
        rules: [Rule] = [],
        fallback: Fallback = .ask,
        primaryBrowser: String? = nil,
        hiddenBrowsers: [String] = [],
        browserOrder: [String] = [],
        onboarded: Bool = false,
        language: Language = .system,
        pickerModifiers: [ModifierKey] = [.option]
    ) {
        self.rules = rules
        self.fallback = fallback
        self.primaryBrowser = primaryBrowser
        self.hiddenBrowsers = hiddenBrowsers
        self.browserOrder = browserOrder
        self.onboarded = onboarded
        self.language = language
        self.pickerModifiers = pickerModifiers
    }

    // Tolerates missing keys so a hand-edited or older config still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        fallback = try c.decodeIfPresent(Fallback.self, forKey: .fallback) ?? .ask
        primaryBrowser = try c.decodeIfPresent(String.self, forKey: .primaryBrowser)
        hiddenBrowsers = try c.decodeIfPresent([String].self, forKey: .hiddenBrowsers) ?? []
        browserOrder = try c.decodeIfPresent([String].self, forKey: .browserOrder) ?? []
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        // An unknown value (e.g. a language from a newer version) falls back instead of rejecting the file.
        language = (try? c.decodeIfPresent(Language.self, forKey: .language)) ?? .system
        pickerModifiers = (try? c.decodeIfPresent([ModifierKey].self, forKey: .pickerModifiers)) ?? [.option]
    }
}
