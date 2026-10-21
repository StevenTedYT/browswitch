import AppKit
import BrowswitchCore
import SwiftUI

/// Translation in the language chosen in Settings ▸ General.
@MainActor
func L(_ key: L10nKey, _ args: String...) -> String {
    L10n.string(key, in: Store.shared.config.language, args)
}

/// Translation with `{0}` rendered in bold, wherever the language puts it.
@MainActor
func L(_ key: L10nKey, bold value: String) -> Text {
    let marker = "\u{1}"
    let parts = L(key, marker).components(separatedBy: marker)
    return Text(parts[0]) + Text(value).bold() + Text(parts.count > 1 ? parts[1] : "")
}

@MainActor
var appLocale: Locale {
    Locale(identifier: Store.shared.config.language.resolved().rawValue)
}

extension MatchKind {
    @MainActor var label: String {
        switch self {
        case .domain: return L(.matchDomain)
        case .contains: return L(.matchContains)
        case .regex: return L(.matchRegex)
        }
    }
}

extension ModifierKey {
    @MainActor var name: String {
        switch self {
        case .control: return L(.keyControl)
        case .option: return L(.keyOption)
        case .shift: return L(.keyShift)
        case .command: return L(.keyCommand)
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option: return .option
        case .shift: return .shift
        case .command: return .command
        }
    }

    static let allFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// True when exactly these keys are held, so ⌥ alone doesn't trigger a ⌥⌘ shortcut and vice versa.
    static func areHeld(_ keys: [ModifierKey]) -> Bool {
        guard !keys.isEmpty else { return false }
        let required = keys.reduce(into: NSEvent.ModifierFlags()) { $0.insert($1.flag) }
        return NSEvent.modifierFlags.intersection(allFlags) == required
    }

    /// "⌥⌘", always in Apple's order.
    static func symbols(_ keys: [ModifierKey]) -> String {
        allCases.filter(keys.contains).map(\.symbol).joined()
    }
}
