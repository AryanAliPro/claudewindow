import AppKit
import SwiftUI

// Renders the app icon and screenshots of every screen from code, so the
// README images and the icon always match the current design.

@MainActor
func renderIcon(to url: URL) {
    // macOS icon grid: 824pt body centred on a 1024pt canvas.
    let view = ZStack {
        AppGlyph(size: 824, shadow: false)
            .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
    }
    .frame(width: 1024, height: 1024)
    let r = ImageRenderer(content: view)
    r.scale = 1
    guard let cg = r.cgImage else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

func mockEngine(_ state: String) -> Engine {
    let e = Engine()
    e.mock = true
    e.now = Date()
    e.account = .ready(email: "you@example.com", plan: "Max")
    e.claudePath = "/Users/you/.local/bin/claude"
    e.updated = e.now.addingTimeInterval(-70)
    e.usage.weekUtil = 0.34
    e.usage.weekReset = e.now.addingTimeInterval(3.4 * 86400)
    e.launchAtLogin = true
    switch state {
    case "ready":
        e.usage.sessionUtil = 0
    case "awaiting":
        e.usage.sessionReset = e.now.addingTimeInterval(4.7 * 3600)
        e.usage.sessionUtil = 0.06
        e.autoStart = true
        e.cloud = .awaiting(enable: true)
    case "failed":
        e.usage.sessionReset = e.now.addingTimeInterval(0.8 * 3600)
        e.usage.sessionUtil = 0.92
        e.autoStart = true
        e.cloud = .failed("The request wasn't approved.")
    case "signedout":
        e.account = .signedOut
    case "missing":
        e.account = .missing
        e.claudePath = nil
    case "checking":
        e.account = .checking
        e.updated = nil
    default: // active
        e.usage.sessionReset = e.now.addingTimeInterval(3 * 3600 + 42 * 60)
        e.usage.sessionUtil = 0.58
        e.autoStart = true
        e.cloud = .on
    }
    return e
}

@MainActor
func snapshot<V: View>(_ view: V, dark: Bool, to url: URL) {
    let host = NSHostingView(rootView: view)
    let size = host.fittingSize
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    win.contentView = host
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

@MainActor
func renderSnapshots(to dir: URL) {
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for dark in [false, true] {
        let suffix = dark ? "-dark" : ""
        for state in ["active", "ready", "awaiting", "failed", "signedout"] {
            let panel = PanelView(e: mockEngine(state))
                .background(Color(nsColor: .windowBackgroundColor))
            snapshot(panel, dark: dark, to: dir.appendingPathComponent("panel-\(state)\(suffix).png"))
        }
        let setups: [(Int, String, String)] = [(0, "active", "welcome"), (1, "missing", "connect-missing"),
                                                (1, "active", "connect"), (2, "ready", "autostart"),
                                                (2, "awaiting", "autostart-awaiting"), (3, "active", "done")]
        for (step, state, name) in setups {
            let flow = OnboardingFlow()
            flow.step = step
            let e = mockEngine(state)
            if name == "autostart" { e.autoStart = false; e.cloud = .off }
            snapshot(OnboardingView(e: e, flow: flow, finish: {}), dark: dark,
                     to: dir.appendingPathComponent("setup-\(name)\(suffix).png"))
        }
    }
}
