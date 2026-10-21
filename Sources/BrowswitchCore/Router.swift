import Foundation

public enum Router {
    public static func firstMatch(for url: URL, sourceApp: String?, in rules: [Rule]) -> Rule? {
        rules.first { $0.enabled && !$0.browser.isEmpty && matches($0, url: url, sourceApp: sourceApp) }
    }

    /// A rule matches when all of its conditions match. A rule without any condition never matches.
    public static func matches(_ rule: Rule, url: URL, sourceApp: String?) -> Bool {
        if rule.hasSourceCondition {
            guard let sourceApp, sourceApp.caseInsensitiveCompare(rule.sourceApp ?? "") == .orderedSame else { return false }
        }
        guard rule.hasURLCondition else { return rule.hasSourceCondition }

        let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rule.matchKind {
        case .domain:
            return domainPatterns(pattern).contains { domainMatches(url, pattern: $0) }
        case .contains:
            return url.absoluteString.range(of: pattern, options: .caseInsensitive) != nil
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            let string = url.absoluteString
            return regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
        }
    }

    /// "youtube.com, youtu.be" → ["youtube.com", "youtu.be"]
    public static func domainPatterns(_ pattern: String) -> [String] {
        pattern
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .map { normalizeDomainPattern(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func normalizeDomainPattern(_ raw: String) -> String {
        var pattern = raw.lowercased()
        if let scheme = pattern.range(of: "://") { pattern = String(pattern[scheme.upperBound...]) }
        if pattern.hasPrefix("www.") { pattern.removeFirst(4) }
        while pattern.hasSuffix("/") { pattern.removeLast() }
        return pattern
    }

    /// "youtube.com" matches youtube.com and its subdomains, "*.google.com" is a wildcard,
    /// and "github.com/acme" also requires the path to be /acme or below it.
    public static func domainMatches(_ url: URL, pattern: String) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }

        let hostPattern: String
        var pathPattern: String?
        if let slash = pattern.firstIndex(of: "/") {
            hostPattern = String(pattern[..<slash])
            pathPattern = String(pattern[slash...])
        } else {
            hostPattern = pattern
        }

        guard hostMatches(host, pattern: hostPattern) else { return false }
        guard let pathPattern else { return true }
        let path = url.path.lowercased()
        return path == pathPattern || path.hasPrefix(pathPattern + "/")
    }

    static func hostMatches(_ host: String, pattern: String) -> Bool {
        if pattern.contains("*") {
            let regex = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
            return host.range(of: "^\(regex)$", options: .regularExpression) != nil
        }
        return host == pattern || host.hasSuffix("." + pattern)
    }

    /// Domain saved when "remember my choice" is ticked in the picker.
    public static func rememberableDomain(for url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
