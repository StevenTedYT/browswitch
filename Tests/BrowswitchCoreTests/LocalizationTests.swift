import XCTest
@testable import BrowswitchCore

final class LocalizationTests: XCTestCase {
    func testEveryLanguageTranslatesEveryKey() {
        for language in Language.allCases where language != .system {
            let table = L10n.tables[language] ?? [:]
            let missing = L10nKey.allCases.filter { table[$0]?.isEmpty ?? true }
            XCTAssertTrue(missing.isEmpty, "\(language): missing \(missing)")
        }
    }

    func testPlaceholdersMatchFrench() {
        let placeholder = try! NSRegularExpression(pattern: #"\{\d\}"#)
        func placeholders(_ text: String) -> Set<String> {
            Set(placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) })
        }
        for language in Language.allCases where language != .system {
            for key in L10nKey.allCases {
                XCTAssertEqual(
                    placeholders(L10n.tables[language]?[key] ?? ""),
                    placeholders(L10n.tables[.fr]?[key] ?? ""),
                    "\(language).\(key)"
                )
            }
        }
    }

    func testArgumentsAreSubstituted() {
        XCTAssertEqual(L10n.string(.testerRule, in: .en, ["Safari", "YouTube"]), "→ Safari, via the rule “YouTube”")
    }

    func testSystemLanguageResolution() {
        XCTAssertEqual(Language.system.resolved(preferred: ["ja-JP", "en-US"]), .ja)
        XCTAssertEqual(Language.system.resolved(preferred: ["pt-BR", "nl-NL"]), .nl)
        XCTAssertEqual(Language.system.resolved(preferred: ["pt-BR"]), .en)
        XCTAssertEqual(Language.de.resolved(preferred: ["fr-FR"]), .de)
    }

    func testConfigToleratesUnknownLanguageAndDefaultsModifiers() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"language":"klingon","rules":[]}"#.utf8))
        XCTAssertEqual(config.language, .system)
        XCTAssertEqual(config.pickerModifiers, [.option])

        let combo = try JSONDecoder().decode(Config.self, from: Data(#"{"pickerModifiers":["option","command"]}"#.utf8))
        XCTAssertEqual(combo.pickerModifiers, [.option, .command])
    }
}
