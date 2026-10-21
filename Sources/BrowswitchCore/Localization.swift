import Foundation

public enum Language: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, fr, en, es, de, it, ja, nl

    public var id: String { rawValue }

    /// Name written in the language itself; nil for `.system`.
    public var nativeName: String? {
        switch self {
        case .system: return nil
        case .fr: return "Français"
        case .en: return "English"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .ja: return "日本語"
        case .nl: return "Nederlands"
        }
    }

    /// `.system` becomes the first supported language in the user's macOS preferences, else English.
    public func resolved(preferred: [String] = Locale.preferredLanguages) -> Language {
        guard self == .system else { return self }
        for identifier in preferred {
            let code = identifier.prefix { $0 != "-" && $0 != "_" }.lowercased()
            if let language = Language(rawValue: code), language != .system { return language }
        }
        return .en
    }
}

public enum L10n {
    /// `{0}`, `{1}`… in the translation are replaced by `args`.
    public static func string(_ key: L10nKey, in language: Language, _ args: [String] = []) -> String {
        var text = tables[language.resolved()]?[key] ?? tables[.en]?[key] ?? key.rawValue
        for (index, arg) in args.enumerated() {
            text = text.replacingOccurrences(of: "{\(index)}", with: arg)
        }
        return text
    }

    static let tables: [Language: [L10nKey: String]] = [
        .fr: Translations.fr,
        .en: Translations.en,
        .es: Translations.es,
        .de: Translations.de,
        .it: Translations.it,
        .ja: Translations.ja,
        .nl: Translations.nl,
    ]
}

public enum L10nKey: String, CaseIterable, Sendable {
    // Picker
    case pickerAlwaysUse, pickerAlwaysUseHelp, pickerHint
    // Menus
    case menuSetDefault, menuOpenClipboard, menuPrimaryBrowser, menuSettings, menuQuit, menuHide
    case menuEdit, menuUndo, menuRedo, menuCut, menuCopy, menuPaste, menuSelectAll
    case menuWindow, menuClose, menuMinimize
    // Settings window
    case settingsTitle, tabGeneral, tabRules, tabBrowsers, tabHistory
    case noBrowser, browserNotFound
    // General
    case defaultSection, isDefaultTitle, isDefaultDetail, notDefaultTitle, notDefaultDetail, setDefault
    case noMatchSection, fallbackLabel, fallbackAsk, fallbackPrimary, primaryBrowser, none, primaryHint
    case pickerShortcutSection, pickerShortcutLabel, pickerShortcutHint, pickerShortcutDisabled
    case keyControl, keyOption, keyShift, keyCommand
    case systemSection, language, systemLanguage, launchAtLogin, configFile, showInFinder
    // Rules
    case rulesIntro, edit, duplicate, delete, noRules, noRulesHint, copySuffix
    case summaryFrom, summaryDomain, summaryContains, summaryRegex, summaryNoCondition, untitledRule
    case matchDomain, matchContains, matchRegex
    // Rule editor
    case editorName, editorNamePrompt, editorIf, editorLinkFrom, anyApp, chooseApp, editorAndURL, editorPattern
    case helpDomain, helpContains, helpRegex, invalidRegex
    case editorThen, editorOpenWith, chooseBrowser, cancel, add, save, needCondition, openPanelPrompt
    // Rule tester
    case testerPrompt, testerFrom, testerAnyApp, testerInvalidURL, testerRule, testerPrimary, testerPicker
    // Browsers
    case browsersIntro, primaryBadge, refreshBrowsers
    // History
    case historyIntro, unknownApp, createRule, reopenWithPicker, copyURL, noHistory, clearHistory
    case reasonRule, reasonPrimary, reasonManual, reasonRemembered, reasonCancelled
}
