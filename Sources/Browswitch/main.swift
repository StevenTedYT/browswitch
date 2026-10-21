import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared

    #if DEBUG
    if let flag = CommandLine.arguments.firstIndex(of: "--screenshots"), CommandLine.arguments.indices.contains(flag + 1) {
        app.setActivationPolicy(.accessory)
        Screenshots.run(into: CommandLine.arguments[flag + 1])
        exit(0)
    }
    #endif

    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
