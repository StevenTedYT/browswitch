import XCTest
@testable import BrowswitchCore

final class RouterTests: XCTestCase {
    private let chrome = "com.google.Chrome"
    private let safari = "com.apple.Safari"
    private let discord = "com.hnc.Discord"

    private func url(_ string: String) -> URL { URL(string: string)! }

    func testDomainMatchesSubdomainsButNotLookalikes() {
        let rule = Rule(pattern: "youtube.com", browser: safari)
        XCTAssertTrue(Router.matches(rule, url: url("https://youtube.com/watch?v=1"), sourceApp: nil))
        XCTAssertTrue(Router.matches(rule, url: url("https://www.youtube.com/"), sourceApp: nil))
        XCTAssertTrue(Router.matches(rule, url: url("https://m.youtube.com/"), sourceApp: nil))
        XCTAssertFalse(Router.matches(rule, url: url("https://notyoutube.com/"), sourceApp: nil))
    }

    func testSeveralDomainsAndNormalization() {
        let rule = Rule(pattern: "https://www.YouTube.com/, youtu.be", browser: safari)
        XCTAssertTrue(Router.matches(rule, url: url("https://youtu.be/abc"), sourceApp: nil))
        XCTAssertTrue(Router.matches(rule, url: url("https://youtube.com"), sourceApp: nil))
    }

    func testWildcardAndPath() {
        let wildcard = Rule(pattern: "*.google.com", browser: chrome)
        XCTAssertTrue(Router.matches(wildcard, url: url("https://docs.google.com/x"), sourceApp: nil))
        XCTAssertFalse(Router.matches(wildcard, url: url("https://google.com/"), sourceApp: nil))

        let path = Rule(pattern: "github.com/acme", browser: chrome)
        XCTAssertTrue(Router.matches(path, url: url("https://github.com/acme"), sourceApp: nil))
        XCTAssertTrue(Router.matches(path, url: url("https://github.com/acme/repo"), sourceApp: nil))
        XCTAssertFalse(Router.matches(path, url: url("https://github.com/acmefoo"), sourceApp: nil))
        XCTAssertFalse(Router.matches(path, url: url("https://github.com/other"), sourceApp: nil))
    }

    func testSourceAppConditions() {
        let fromDiscord = Rule(sourceApp: discord, browser: chrome)
        XCTAssertTrue(Router.matches(fromDiscord, url: url("https://anything.com"), sourceApp: discord))
        XCTAssertFalse(Router.matches(fromDiscord, url: url("https://anything.com"), sourceApp: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(Router.matches(fromDiscord, url: url("https://anything.com"), sourceApp: nil))

        let both = Rule(sourceApp: discord, pattern: "youtube.com", browser: safari)
        XCTAssertTrue(Router.matches(both, url: url("https://youtube.com"), sourceApp: discord))
        XCTAssertFalse(Router.matches(both, url: url("https://twitch.tv"), sourceApp: discord))
    }

    func testContainsAndRegex() {
        let contains = Rule(matchKind: .contains, pattern: "meet", browser: chrome)
        XCTAssertTrue(Router.matches(contains, url: url("https://MEET.google.com/abc"), sourceApp: nil))

        let regex = Rule(matchKind: .regex, pattern: #"^https://[^/]+\.atlassian\.net/"#, browser: chrome)
        XCTAssertTrue(Router.matches(regex, url: url("https://acme.atlassian.net/browse/X-1"), sourceApp: nil))
        XCTAssertFalse(Router.matches(regex, url: url("https://atlassian.com"), sourceApp: nil))

        let broken = Rule(matchKind: .regex, pattern: "(", browser: chrome)
        XCTAssertFalse(Router.matches(broken, url: url("https://a.com"), sourceApp: nil))
    }

    func testRuleWithoutConditionNeverMatches() {
        XCTAssertFalse(Router.matches(Rule(browser: chrome), url: url("https://a.com"), sourceApp: discord))
    }

    func testFirstMatchRespectsOrderAndSkipsDisabled() {
        let rules = [
            Rule(enabled: false, pattern: "youtube.com", browser: "disabled"),
            Rule(sourceApp: discord, browser: chrome),
            Rule(pattern: "youtube.com", browser: safari),
        ]
        XCTAssertEqual(Router.firstMatch(for: url("https://youtube.com"), sourceApp: discord, in: rules)?.browser, chrome)
        XCTAssertEqual(Router.firstMatch(for: url("https://youtube.com"), sourceApp: nil, in: rules)?.browser, safari)
        XCTAssertNil(Router.firstMatch(for: url("https://twitch.tv"), sourceApp: nil, in: rules))
    }

    func testRememberableDomain() {
        XCTAssertEqual(Router.rememberableDomain(for: url("https://www.YouTube.com/watch")), "youtube.com")
        XCTAssertNil(Router.rememberableDomain(for: url("file:///tmp/a.html")))
    }

    func testConfigDecodesWithMissingKeys() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"fallback":"primary"}"#.utf8))
        XCTAssertEqual(config.fallback, .primary)
        XCTAssertTrue(config.rules.isEmpty)
    }
}
