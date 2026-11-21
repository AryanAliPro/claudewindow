import AppKit
import SwiftUI

/// Template image for the menu bar: a ring that empties as the window runs down.
/// `progress` is the share of the window left; nil draws a dashed "ready" ring.
func ringImage(progress: Double?, height: CGFloat = 16, alert: Bool = false) -> NSImage {
    let size = NSSize(width: height, height: height)
    let img = NSImage(size: size, flipped: false) { rect in
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let lw = height * 0.15
        let r = height / 2 - lw / 2 - height * 0.06
        let track = NSBezierPath()
        track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
        track.lineWidth = lw
        if let p = progress {
            NSColor.black.withAlphaComponent(0.25).setStroke()
            track.stroke()
            if p > 0.005 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * CGFloat(min(1, p)), clockwise: true)
                arc.lineWidth = lw
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
        } else {
            NSColor.black.withAlphaComponent(alert ? 0.9 : 0.75).setStroke()
            if !alert { track.setLineDash([lw * 1.05, lw * 1.05], count: 2, phase: 0) }
            track.stroke()
            if alert {
                let dot = NSBezierPath(ovalIn: NSRect(x: c.x - lw * 0.7, y: c.y - lw * 0.7, width: lw * 1.4, height: lw * 1.4))
                NSColor.black.setFill()
                dot.fill()
            }
        }
        return true
    }
    img.isTemplate = true
    return img
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine = Engine()
    let flow = OnboardingFlow()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        let actions = PanelActions(
            openSetup: { [weak self] in self?.showSetup() },
            openAbout: { [weak self] in self?.showAbout() },
            uninstall: { [weak self] in self?.uninstall() })
        let host = NSHostingController(rootView: PanelView(e: engine, actions: actions))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        if let b = item.button {
            b.target = self
            b.action = #selector(togglePanel)
            b.imagePosition = .imageLeading
        }
        engine.onChange = { [weak self] in self?.refreshItem() }
        engine.start()
        refreshItem()

        if !defaults.bool(forKey: Key.onboarded) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showSetup() }
        }
    }

    func refreshItem() {
        guard let b = item.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        var text = ""
        if !engine.account.isReady && engine.account != .checking {
            b.image = ringImage(progress: nil, alert: true)
        } else if let r = engine.remaining {
            b.image = ringImage(progress: r / windowLength)
            text = Fmt.compact(r)
        } else {
            b.image = ringImage(progress: nil)
            if engine.starting { text = "…" }
        }
        b.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [.font: font, .baselineOffset: 0.5])
        b.toolTip = engine.windowEnd.map { "\(appName): resets at \(Fmt.time($0))" } ?? appName
    }

    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let b = item.button else { return }
        engine.panelOpened()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: Setup window

    func showSetup() {
        popover.performClose(nil)
        if setupWindow == nil {
            flow.step = engine.account.isReady && defaults.bool(forKey: Key.onboarded) ? 2 : 0
            let view = OnboardingView(e: engine, flow: flow) { [weak self] in self?.finishSetup() }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: view)
            w.title = "\(appName) Setup"
            w.delegate = self
            w.center()
            setupWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    func finishSetup() {
        defaults.set(true, forKey: Key.onboarded)
        setupWindow?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.togglePanel() }
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == setupWindow {
            defaults.set(true, forKey: Key.onboarded)
            setupWindow = nil
        }
    }

    // MARK: About / Uninstall

    func showAbout() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .applicationVersion: version,
            .version: "",
            .credits: NSAttributedString(
                string: "Keeps your Claude usage window rolling.\nOpen source. Not affiliated with Anthropic.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    func uninstall() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let cloudOn = engine.cloud == .on || engine.cloud.stored == "on"
        let alert = NSAlert()
        alert.messageText = "Uninstall \(appName)?"
        alert.informativeText = cloudOn
            ? "This removes the app, its settings and the login item.\n\nThe hourly schedule on your Claude account keeps running until you delete it. We'll open that page for you; delete the routine named “\(routineName)”."
            : "This removes the app, its settings and the login item."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        engine.removeLocalData()
        if cloudOn { NSWorkspace.shared.open(URL(string: "https://claude.ai/code/routines")!) }
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
