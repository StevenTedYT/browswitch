#if DEBUG
import AppKit
import BrowswitchCore
import SwiftUI

/// Debug builds only: `Browswitch --screenshots <dir>` renders the README images (see scripts/screenshots.sh).
/// The real views are captured with AppKit, then laid out on a wallpaper with SwiftUI's ImageRenderer.
@MainActor
enum Screenshots {
    static func run(into directory: String) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        BrowserManager.shared.refresh()
        Store.shared.clearHistory()
        seedHistory()

        let model = PickerModel(
            url: URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!,
            source: SourceApp(bundleID: "com.hnc.Discord"),
            browsers: BrowserManager.shared.ordered(includeHidden: false),
            selection: 0
        )
        model.remember = true
        save(PickerShowcase(picker: capture(PickerView(model: model, cornerRadius: 18))), to: dir.appendingPathComponent("picker.jpg"))

        // AppKit does not draw the selected tab offscreen, so the tab bar is drawn by the showcase.
        let tabs: [(file: String, title: String, view: AnyView)] = [
            ("general", L(.tabGeneral), AnyView(GeneralSettingsView())),
            ("rules", L(.tabRules), AnyView(RulesSettingsView())),
            ("browsers", L(.tabBrowsers), AnyView(BrowsersSettingsView())),
            ("history", L(.tabHistory), AnyView(HistorySettingsView())),
        ]
        for tab in tabs {
            let content = capture(tab.view.padding([.horizontal, .bottom]).frame(width: 720, height: 630).background(Showcase.windowBackground))
            save(
                WindowShowcase(title: L(.settingsTitle), tabs: tabs.map(\.title), selectedTab: tab.title, content: content),
                to: dir.appendingPathComponent("\(tab.file).jpg")
            )
        }

        if let rule = Store.shared.config.rules.first(where: { $0.hasSourceCondition && $0.hasURLCondition }) {
            let editor = capture(RuleEditor(rule: rule, isNew: false) { _ in }.background(Showcase.windowBackground))
            save(WindowShowcase(title: nil, tabs: [], selectedTab: nil, content: editor), to: dir.appendingPathComponent("rule-editor.jpg"))
        }
    }

    private static func seedHistory() {
        let samples: [(minutesAgo: Double, source: String, url: String, browser: String?, reason: HistoryReason)] = [
            (42, "im.riot.app", "https://news.ycombinator.com/item?id=41234567", nil, .cancelled),
            (35, "com.figma.Desktop", "https://docs.google.com/document/d/1aB2c/edit", "com.google.Chrome", .rule("Google Workspace")),
            (21, "com.apple.MobileSMS", "https://www.figma.com/design/x7Yz/Design-system", "com.apple.Safari", .remembered("figma.com")),
            (12, "com.microsoft.VSCode", "https://github.com/swiftlang/swift/pull/76543", "com.google.Chrome", .rule("GitHub from VS Code")),
            (6, "com.apple.mail", "https://youtu.be/jNQXAC9IVRw", "com.apple.Safari", .rule("YouTube in Safari")),
            (1, "com.hnc.Discord", "https://store.steampowered.com/app/620/Portal_2/", "com.google.Chrome", .rule("Discord")),
        ]
        for sample in samples {
            Store.shared.record(HistoryEntry(
                date: Date().addingTimeInterval(-sample.minutesAgo * 60),
                url: URL(string: sample.url)!,
                source: SourceApp(bundleID: sample.source),
                browserID: sample.browser,
                reason: sample.reason
            ))
        }
    }

    private static func capture<V: View>(_ view: V) -> NSImage {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))

        let image = NSImage(size: size)
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            image.addRepresentation(rep)
        }
        window.orderOut(nil)
        return image
    }

    private static func save<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        // JPEG: the images are opaque, and PNG gradients weigh several MB each.
        guard let image = renderer.cgImage,
              let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
        try? jpeg.write(to: url)
    }
}

private enum Showcase {
    static let windowBackground = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let titleBar = Color(red: 0.17, green: 0.17, blue: 0.17)
}

private struct Wallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.09, blue: 0.42),
                Color(red: 0.42, green: 0.15, blue: 0.62),
                Color(red: 0.13, green: 0.10, blue: 0.36),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        // Overlays don't affect layout, so the oversized glows can't grow the canvas.
        .overlay {
            Circle()
                .fill(Color(red: 0.80, green: 0.32, blue: 0.86).opacity(0.55))
                .frame(width: 720, height: 720)
                .blur(radius: 170)
                .offset(x: -320, y: 220)
        }
        .overlay {
            Circle()
                .fill(Color(red: 0.22, green: 0.38, blue: 0.98).opacity(0.5))
                .frame(width: 640, height: 640)
                .blur(radius: 160)
                .offset(x: 380, y: -240)
        }
        .clipped()
    }
}

private struct MenuBar: View {
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "apple.logo")
            Text("Discord").fontWeight(.bold)
            Text("File")
            Text("Edit")
            Text("View")
            Spacer()
            Image(systemName: "arrow.triangle.branch")
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Tue Oct 21  11:58")
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 26)
        .background(Color.black.opacity(0.22))
    }
}

private struct PickerShowcase: View {
    let picker: NSImage

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()
            MenuBar()
            Image(nsImage: picker)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(white: 0.12).opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 40, y: 24)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: 12)
        }
        .frame(width: picker.size.width + 420, height: picker.size.height + 280)
    }
}

private struct WindowShowcase: View {
    /// nil draws a sheet: no title bar.
    let title: String?
    let tabs: [String]
    let selectedTab: String?
    let content: NSImage

    private var height: CGFloat {
        content.size.height + (title == nil ? 0 : 28) + (tabs.isEmpty ? 0 : 50)
    }

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 0) {
                if let title {
                    TitleBar(title: title)
                }
                if !tabs.isEmpty {
                    TabBar(tabs: tabs, selected: selectedTab)
                }
                Image(nsImage: content)
            }
            .frame(width: content.size.width)
            .background(Showcase.windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 36, y: 20)
        }
        .frame(width: content.size.width + 140, height: height + 140)
    }
}

private struct TabBar: View {
    let tabs: [String]
    let selected: String?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(tab == selected ? 1 : 0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(tab == selected ? 0.24 : 0))
                    )
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }
}

private struct TitleBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) {
                Circle().fill($0).frame(width: 12, height: 12)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .overlay(
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        )
        .background(Showcase.titleBar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1)
        }
    }
}
#endif
