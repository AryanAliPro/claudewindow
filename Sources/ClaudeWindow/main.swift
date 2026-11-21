import AppKit
import SwiftUI

// Command-line helpers, used for development, docs and support:
//   --status                 print current usage and auto-start state
//   --render-icon <png>      draw the 1024px app icon
//   --snapshots <dir>        render every screen (light and dark) as PNGs
//   --remove-data            remove the login item and local settings

let args = CommandLine.arguments

func arg(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if let out = arg(after: "--render-icon") {
    _ = NSApplication.shared
    MainActor.assumeIsolated { renderIcon(to: URL(fileURLWithPath: out)) }
    exit(0)
}

if let dir = arg(after: "--snapshots") {
    _ = NSApplication.shared
    MainActor.assumeIsolated { renderSnapshots(to: URL(fileURLWithPath: dir)) }
    exit(0)
}

if args.contains("--remove-data") {
    Engine().removeLocalData()
    print("Removed login item and local data.")
    exit(0)
}

if args.contains("--status") {
    let e = Engine()
    e.load()
    e.checkAccount {
        guard e.account.isReady else { print("Account: \(e.account)"); exit(1) }
        e.refresh {
            e.now = Date()
            if let end = e.windowEnd, let r = e.remaining {
                let (h, m) = Fmt.hm(r)
                print("Window resets at \(Fmt.time(end)) (\(h)h \(m)m left)")
            } else {
                print("No active window")
            }
            print("Session: \(Fmt.percent(e.sessionUtil))   Week: \(Fmt.percent(e.weekUtil))")
            print("Auto-start: \(e.autoStart ? "on" : "off")   Closed-lid: \(e.cloud)")
            if let n = e.notice { print("Notice: \(n)") }
            exit(0)
        }
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
