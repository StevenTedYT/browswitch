import AppKit
import BrowswitchCore
import SwiftUI

@MainActor
final class PickerModel: ObservableObject {
    let url: URL
    let source: SourceApp?
    let browsers: [Browser]
    let domain: String?

    @Published var selection: Int
    @Published var remember = false

    var onChoose: (Browser) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(url: URL, source: SourceApp?, browsers: [Browser], selection: Int) {
        self.url = url
        self.source = source
        self.browsers = browsers
        self.selection = selection
        domain = Router.rememberableDomain(for: url)
    }

    func move(_ delta: Int) {
        selection = (selection + delta + browsers.count) % browsers.count
    }

    func choose(at index: Int) {
        guard browsers.indices.contains(index) else { return }
        onChoose(browsers[index])
    }

    func chooseSelection() { choose(at: selection) }
}

/// Borderless panels refuse key status by default, which would disable keyboard shortcuts.
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    static let shared = PickerController()

    private static let cornerRadius: CGFloat = 18
    // Hardware key codes, so digits work on AZERTY keyboards too (top row + keypad).
    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]

    private var queue: [(url: URL, source: SourceApp?)] = []
    private var panel: PickerPanel?
    private var model: PickerModel?
    private var keyMonitor: Any?

    func enqueue(url: URL, source: SourceApp?) {
        queue.append((url, source))
        if panel == nil { showNext() }
    }

    private func showNext() {
        guard panel == nil, !queue.isEmpty else { return }
        let (url, source) = queue.removeFirst()
        let browsers = BrowserManager.shared.ordered(includeHidden: false)
        guard !browsers.isEmpty else {
            NSSound.beep()
            return
        }

        let primary = Store.shared.config.primaryBrowser
        let selection = browsers.firstIndex { $0.id.caseInsensitiveCompare(primary ?? "") == .orderedSame } ?? 0
        let model = PickerModel(url: url, source: source, browsers: browsers, selection: selection)
        model.onChoose = { [weak self] in self?.choose($0) }
        model.onCancel = { [weak self] in self?.cancel() }
        self.model = model

        let hosting = NSHostingView(rootView: PickerView(model: model, cornerRadius: Self.cornerRadius))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        let background = NSVisualEffectView(frame: hosting.frame)
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        background.addSubview(hosting)

        let panel = PickerPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.setFrameOrigin(Self.origin(for: size))
        self.panel = panel

        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    private func choose(_ browser: Browser) {
        guard let model else { return }
        if model.remember, let domain = model.domain {
            Store.shared.rememberDomain(domain, browser: browser.id)
        }
        let reason: HistoryReason = model.remember ? .remembered(model.domain ?? "") : .manual
        LinkRouter.shared.open(model.url, in: browser, source: model.source, reason: reason)
        close()
    }

    private func cancel() {
        guard let model else { return }
        LinkRouter.shared.recordCancelled(model.url, source: model.source)
        close()
    }

    private func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        DispatchQueue.main.async { [weak self] in self?.showNext() }
    }

    func windowDidResignKey(_ notification: Notification) {
        cancel()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let model = self.model, event.window === self.panel else { return event }
            switch event.keyCode {
            case 53: model.onCancel() // Escape
            case 36, 76: model.chooseSelection() // Return, keypad Enter
            case 123: model.move(-1) // ←
            case 124, 48: model.move(1) // →, Tab
            case 49: model.remember.toggle() // Space
            default:
                guard let number = Self.digitKeyCodes[event.keyCode], number <= model.browsers.count else { return event }
                model.choose(at: number - 1)
            }
            return nil
        }
    }

    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.12)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    let cornerRadius: CGFloat

    private var width: CGFloat { max(420, CGFloat(model.browsers.count) * 88 + 32) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(spacing: 2) {
                ForEach(Array(model.browsers.enumerated()), id: \.element.id) { index, browser in
                    BrowserCell(browser: browser, number: index < 9 ? index + 1 : nil, selected: model.selection == index)
                        .onHover { if $0 { model.selection = index } }
                        .onTapGesture { model.choose(at: index) }
                }
            }
            .frame(maxWidth: .infinity)

            footer
        }
        .padding(16)
        .frame(width: width)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let source = model.source {
                    Image(nsImage: source.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(source.name)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(model.url.host ?? model.url.absoluteString)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Text(model.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let domain = model.domain {
                Toggle(isOn: $model.remember) {
                    L(.pickerAlwaysUse, bold: domain)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .help(L(.pickerAlwaysUseHelp))
            }
            Spacer(minLength: 12)
            Text(L(.pickerHint))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct BrowserCell: View {
    let browser: Browser
    let number: Int?
    let selected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Text(number.map(String.init) ?? " ")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(nsImage: browser.icon)
                .resizable()
                .frame(width: 56, height: 56)
            Text(browser.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: 86)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.accentColor.opacity(0.3) : Color.clear)
        )
        .contentShape(Rectangle())
        .help(browser.name)
    }
}
