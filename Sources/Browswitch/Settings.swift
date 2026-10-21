import AppKit
import BrowswitchCore
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var languageObserver: AnyCancellable?

    func show() {
        BrowserManager.shared.refresh()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
            languageObserver = Store.shared.$config
                .map(\.language)
                .removeDuplicates()
                .sink { [weak window] _ in
                    DispatchQueue.main.async { window?.title = L(.settingsTitle) }
                }
        }
        // Show in the Dock and ⌘-Tab while the window is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L(.tabGeneral), systemImage: "gearshape") }
            RulesSettingsView()
                .tabItem { Label(L(.tabRules), systemImage: "list.bullet.rectangle") }
            BrowsersSettingsView()
                .tabItem { Label(L(.tabBrowsers), systemImage: "globe") }
            HistorySettingsView()
                .tabItem { Label(L(.tabHistory), systemImage: "clock") }
        }
        // Rebuilds every view, so all text switches to the new language at once.
        .id(store.config.language)
        .padding()
        .frame(width: 720, height: 680)
    }
}

// MARK: - Shared pieces

struct BrowserLabel: View {
    @ObservedObject private var browsers = BrowserManager.shared
    let id: String

    var body: some View {
        if let browser = browsers.browser(withID: id) {
            HStack(spacing: 6) {
                Image(nsImage: browser.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(browser.name)
            }
        } else {
            Label(id.isEmpty ? L(.noBrowser) : L(.browserNotFound, id), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

/// Menu picker items with an app icon.
struct AppMenuLabel: View {
    let name: String
    let icon: NSImage

    var body: some View {
        Label {
            Text(name)
        } icon: {
            Image(nsImage: AppInfo.smallIcon(icon))
        }
    }
}

// MARK: - Général

struct GeneralSettingsView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var browsers = BrowserManager.shared
    @State private var isDefault = DefaultBrowser.isSelf
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section(L(.defaultSection)) {
                HStack(spacing: 10) {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isDefault ? .green : .orange)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(isDefault ? .isDefaultTitle : .notDefaultTitle))
                            .fontWeight(.medium)
                        Text(L(isDefault ? .isDefaultDetail : .notDefaultDetail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !isDefault {
                        Button(L(.setDefault)) {
                            DefaultBrowser.makeSelfDefault { isDefault = DefaultBrowser.isSelf }
                        }
                    }
                }
            }

            Section(L(.noMatchSection)) {
                Picker(L(.fallbackLabel), selection: $store.config.fallback) {
                    Text(L(.fallbackAsk)).tag(Fallback.ask)
                    Text(L(.fallbackPrimary)).tag(Fallback.primary)
                }
                Picker(L(.primaryBrowser), selection: $store.config.primaryBrowser) {
                    Text(L(.none)).tag(String?.none)
                    ForEach(browsers.ordered(includeHidden: true)) { browser in
                        AppMenuLabel(name: browser.name, icon: browser.icon).tag(String?.some(browser.id))
                    }
                }
                Text(L(.primaryHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L(.pickerShortcutSection)) {
                HStack {
                    Text(L(.pickerShortcutLabel))
                    Spacer()
                    ForEach(ModifierKey.allCases) { key in
                        Toggle("\(key.symbol) \(key.name)", isOn: modifierBinding(key))
                            .toggleStyle(KeyCapToggleStyle())
                    }
                }
                Group {
                    if store.config.pickerModifiers.isEmpty {
                        Text(L(.pickerShortcutDisabled))
                    } else {
                        L(.pickerShortcutHint, bold: ModifierKey.symbols(store.config.pickerModifiers))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(L(.systemSection)) {
                Picker(L(.language), selection: $store.config.language) {
                    Text(L(.systemLanguage)).tag(Language.system)
                    Divider()
                    ForEach(Language.allCases.filter { $0 != .system }) { language in
                        Text(language.nativeName ?? language.rawValue).tag(language)
                    }
                }
                Toggle(L(.launchAtLogin), isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Text(L(.configFile))
                    Spacer()
                    Button(L(.showInFinder)) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { isDefault = DefaultBrowser.isSelf }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isSelf
        }
    }

    private func modifierBinding(_ key: ModifierKey) -> Binding<Bool> {
        Binding(
            get: { store.config.pickerModifiers.contains(key) },
            set: { held in
                var keys = Set(store.config.pickerModifiers)
                if held { keys.insert(key) } else { keys.remove(key) }
                store.config.pickerModifiers = ModifierKey.allCases.filter(keys.contains)
            }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// A key cap that lights up when held keys include it.
private struct KeyCapToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(.callout.weight(configuration.isOn ? .semibold : .regular))
                .foregroundStyle(configuration.isOn ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(shape.fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.06)))
                .overlay(shape.strokeBorder(Color.primary.opacity(configuration.isOn ? 0 : 0.15)))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Règles

struct RulesSettingsView: View {
    @ObservedObject private var store = Store.shared
    @State private var selection: Rule.ID?
    @State private var editing: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(.rulesIntro))
                .font(.callout)
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach($store.config.rules) { $rule in
                    RuleRow(rule: $rule).tag(rule.id)
                }
                .onMove { store.config.rules.move(fromOffsets: $0, toOffset: $1) }
            }
            .contextMenu(forSelectionType: Rule.ID.self) { ids in
                if let id = ids.first, let rule = rule(id) {
                    Button(L(.edit)) { editing = rule }
                    Button(L(.duplicate)) { duplicate(rule) }
                    Divider()
                    Button(L(.delete), role: .destructive) { delete(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first { editing = rule(id) }
            }
            .onDeleteCommand { if let selection { delete(selection) } }
            .overlay {
                if store.config.rules.isEmpty {
                    VStack(spacing: 6) {
                        Text(L(.noRules)).font(.headline)
                        Text(L(.noRulesHint))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 4) {
                Button {
                    editing = Rule(browser: store.config.primaryBrowser ?? "")
                } label: {
                    Image(systemName: "plus").frame(width: 16)
                }
                Button {
                    if let selection { delete(selection) }
                } label: {
                    Image(systemName: "minus").frame(width: 16)
                }
                .disabled(selection == nil)
                Button(L(.edit)) { editing = selection.flatMap(rule) }
                    .disabled(selection == nil)
                Spacer()
            }

            Divider().padding(.vertical, 4)
            RuleTester()
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, isNew: self.rule(rule.id) == nil) { save($0) }
        }
    }

    private func rule(_ id: Rule.ID) -> Rule? {
        store.config.rules.first { $0.id == id }
    }

    private func save(_ rule: Rule) {
        if let index = store.config.rules.firstIndex(where: { $0.id == rule.id }) {
            store.config.rules[index] = rule
        } else {
            store.config.rules.append(rule)
            selection = rule.id
        }
    }

    private func duplicate(_ rule: Rule) {
        var copy = rule
        copy.id = UUID()
        copy.name = rule.name.isEmpty ? "" : L(.copySuffix, rule.name)
        let index = (store.config.rules.firstIndex(of: rule) ?? store.config.rules.count - 1) + 1
        store.config.rules.insert(copy, at: index)
        selection = copy.id
    }

    private func delete(_ id: Rule.ID) {
        store.config.rules.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }
}

@MainActor
enum RuleSummary {
    /// Like `Rule.displayName`, but shows the app name instead of its bundle identifier.
    static func title(for rule: Rule) -> String {
        if rule.name.trimmingCharacters(in: .whitespaces).isEmpty, !rule.hasURLCondition, let sourceApp = rule.sourceApp, rule.hasSourceCondition {
            return SourceApp(bundleID: sourceApp).name
        }
        return rule.displayName.isEmpty ? L(.untitledRule) : rule.displayName
    }

    static func text(for rule: Rule) -> String {
        var parts: [String] = []
        if let sourceApp = rule.sourceApp, rule.hasSourceCondition {
            parts.append(L(.summaryFrom, SourceApp(bundleID: sourceApp).name))
        }
        if rule.hasURLCondition {
            switch rule.matchKind {
            case .domain: parts.append(L(.summaryDomain, rule.pattern))
            case .contains: parts.append(L(.summaryContains, rule.pattern))
            case .regex: parts.append(L(.summaryRegex, rule.pattern))
            }
        }
        return parts.isEmpty ? L(.summaryNoCondition) : parts.joined(separator: "  ·  ")
    }
}

private struct RuleRow: View {
    @Binding var rule: Rule

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.enabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
            if let sourceApp = rule.sourceApp, rule.hasSourceCondition {
                Image(nsImage: SourceApp(bundleID: sourceApp).icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "link")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(RuleSummary.title(for: rule)).fontWeight(.medium)
                Text(RuleSummary.text(for: rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            BrowserLabel(id: rule.browser)
                .frame(minWidth: 140, alignment: .leading)
        }
        .padding(.vertical, 2)
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var browsers = BrowserManager.shared

    @State private var rule: Rule
    @State private var knownApps: [SourceApp]
    let isNew: Bool
    let onSave: (Rule) -> Void

    init(rule: Rule, isNew: Bool, onSave: @escaping (Rule) -> Void) {
        _rule = State(initialValue: rule)
        var apps = KnownApps.list()
        if let id = rule.sourceApp, rule.hasSourceCondition,
           !apps.contains(where: { $0.bundleID.caseInsensitiveCompare(id) == .orderedSame }) {
            apps.insert(SourceApp(bundleID: id), at: 0)
        }
        _knownApps = State(initialValue: apps)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var sourceBinding: Binding<String> {
        Binding(
            get: { rule.sourceApp ?? "" },
            set: { rule.sourceApp = $0.isEmpty ? nil : $0 }
        )
    }

    private var regexError: Bool {
        rule.matchKind == .regex && rule.hasURLCondition
            && (try? NSRegularExpression(pattern: rule.pattern)) == nil
    }

    private var isValid: Bool {
        !rule.browser.isEmpty && (rule.hasSourceCondition || rule.hasURLCondition) && !regexError
    }

    private var patternPrompt: String {
        switch rule.matchKind {
        case .domain: return "youtube.com, youtu.be"
        case .contains: return "meet.google"
        case .regex: return #"^https://.*\.atlassian\.net/"#
        }
    }

    private var patternHelp: String {
        switch rule.matchKind {
        case .domain: return L(.helpDomain)
        case .contains: return L(.helpContains)
        case .regex: return L(.helpRegex)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(L(.editorName), text: $rule.name, prompt: Text(L(.editorNamePrompt)))
                }

                Section(L(.editorIf)) {
                    HStack {
                        Picker(L(.editorLinkFrom), selection: sourceBinding) {
                            Text(L(.anyApp)).tag("")
                            Divider()
                            ForEach(knownApps, id: \.bundleID) { app in
                                AppMenuLabel(name: app.name, icon: app.icon).tag(app.bundleID)
                            }
                        }
                        Button(L(.chooseApp), action: chooseApp)
                    }
                    Picker(L(.editorAndURL), selection: $rule.matchKind) {
                        ForEach(MatchKind.allCases) { Text($0.label).tag($0) }
                    }
                    TextField(text: $rule.pattern, prompt: Text(patternPrompt)) {
                        Text(L(.editorPattern)).font(.body)
                    }
                    .font(.body.monospaced())
                    Text(patternHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if regexError {
                        Text(L(.invalidRegex)).font(.caption).foregroundStyle(.red)
                    }
                }

                Section(L(.editorThen)) {
                    Picker(L(.editorOpenWith), selection: $rule.browser) {
                        if rule.browser.isEmpty {
                            Text(L(.chooseBrowser)).tag("")
                        }
                        ForEach(browsers.ordered(includeHidden: true)) { browser in
                            AppMenuLabel(name: browser.name, icon: browser.icon).tag(browser.id)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !rule.hasSourceCondition && !rule.hasURLCondition {
                    Text(L(.needCondition))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L(.cancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? L(.add) : L(.save)) {
                    onSave(finalized())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 540, height: 520)
    }

    private func finalized() -> Rule {
        var result = rule
        result.pattern = result.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let source = result.sourceApp.flatMap { id in knownApps.first { $0.bundleID == id }?.name }
            result.name = [source, result.hasURLCondition ? result.pattern : nil]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        return result
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L(.openPanelPrompt)
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !knownApps.contains(where: { $0.bundleID == id }) {
            knownApps.insert(SourceApp(bundleID: id, url: url), at: 0)
        }
        rule.sourceApp = id
    }
}

/// Shows which rule would handle a URL, without opening anything.
private struct RuleTester: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var browsers = BrowserManager.shared
    @State private var urlText = ""
    @State private var source = ""
    @State private var apps = KnownApps.list()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L(.testerPrompt), text: $urlText)
                    .textFieldStyle(.roundedBorder)
                Picker(L(.testerFrom), selection: $source) {
                    Text(L(.testerAnyApp)).tag("")
                    Divider()
                    ForEach(apps, id: \.bundleID) { app in
                        AppMenuLabel(name: app.name, icon: app.icon).tag(app.bundleID)
                    }
                }
                .frame(width: 230)
            }
            if let result {
                Text(result)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var result: String? {
        var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.host != nil else { return L(.testerInvalidURL) }

        if let rule = Router.firstMatch(for: url, sourceApp: source.isEmpty ? nil : source, in: store.config.rules) {
            let name = browsers.browser(withID: rule.browser)?.name ?? rule.browser
            return L(.testerRule, name, RuleSummary.title(for: rule))
        }
        if store.config.fallback == .primary, let primary = browsers.browser(withID: store.config.primaryBrowser) {
            return L(.testerPrimary, primary.name)
        }
        return L(.testerPicker)
    }
}

// MARK: - Navigateurs

struct BrowsersSettingsView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var browsers = BrowserManager.shared

    var body: some View {
        let ordered = browsers.ordered(includeHidden: true)
        VStack(alignment: .leading, spacing: 8) {
            Text(L(.browsersIntro))
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, browser in
                    HStack(spacing: 10) {
                        Toggle("", isOn: visibleBinding(browser))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        Image(nsImage: browser.icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text(browser.name)
                        if browser.id.caseInsensitiveCompare(store.config.primaryBrowser ?? "") == .orderedSame {
                            Text(L(.primaryBadge))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        }
                        Spacer()
                        Text(browser.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    var ids = ordered.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    store.config.browserOrder = ids
                }
            }

            HStack {
                Spacer()
                Button(L(.refreshBrowsers)) { browsers.refresh() }
            }
        }
    }

    private func visibleBinding(_ browser: Browser) -> Binding<Bool> {
        Binding(
            get: { !store.config.hiddenBrowsers.contains { $0.caseInsensitiveCompare(browser.id) == .orderedSame } },
            set: { visible in
                store.config.hiddenBrowsers.removeAll { $0.caseInsensitiveCompare(browser.id) == .orderedSame }
                if !visible { store.config.hiddenBrowsers.append(browser.id) }
            }
        )
    }
}

// MARK: - Historique

struct HistorySettingsView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var browsers = BrowserManager.shared
    @State private var draft: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(.historyIntro))
                .font(.callout)
                .foregroundStyle(.secondary)

            List(store.history) { entry in
                HStack(spacing: 10) {
                    if let source = entry.source {
                        Image(nsImage: source.icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "questionmark.app")
                            .frame(width: 22, height: 22)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.url.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(entry.source?.name ?? L(.unknownApp))  ·  \(timestamp(entry.date))  ·  \(entry.reason.text)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let id = entry.browserID, let browser = browsers.browser(withID: id) {
                        Image(nsImage: browser.icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .help(browser.name)
                    }
                    Menu {
                        Button(L(.createRule)) { draft = makeDraft(from: entry) }
                        Button(L(.reopenWithPicker)) {
                            LinkRouter.shared.handle(entry.url, from: entry.source, forcePicker: true)
                        }
                        Button(L(.copyURL)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if store.history.isEmpty {
                    Text(L(.noHistory))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button(L(.clearHistory)) { store.clearHistory() }
                    .disabled(store.history.isEmpty)
            }
        }
        .sheet(item: $draft) { rule in
            RuleEditor(rule: rule, isNew: true) { store.config.rules.append($0) }
        }
    }

    /// Time only for today's links, date and time for older ones.
    private func timestamp(_ date: Date) -> String {
        let style = Calendar.current.isDateInToday(date)
            ? Date.FormatStyle(date: .omitted, time: .shortened)
            : Date.FormatStyle(date: .abbreviated, time: .shortened)
        return date.formatted(style.locale(appLocale))
    }

    private func makeDraft(from entry: HistoryEntry) -> Rule {
        Rule(
            sourceApp: entry.source?.bundleID,
            matchKind: .domain,
            pattern: Router.rememberableDomain(for: entry.url) ?? "",
            browser: entry.browserID ?? store.config.primaryBrowser ?? ""
        )
    }
}
