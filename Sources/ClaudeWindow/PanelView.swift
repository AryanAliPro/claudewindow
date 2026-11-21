import SwiftUI

struct PanelActions {
    var openSetup: () -> Void = {}
    var openAbout: () -> Void = {}
    var uninstall: () -> Void = {}
}

/// The panel that drops down from the menu bar.
struct PanelView: View {
    @ObservedObject var e: Engine
    var actions = PanelActions()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Hairline()
            Group {
                if e.account.isReady || (e.account == .checking && e.updated != nil) {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        usage
                        autoStart
                        if let n = e.notice { noticeView(n) }
                    }
                } else {
                    setupNeeded
                }
            }
            .padding(16)
            if e.account.isReady {
                Hairline()
                footer
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
            }
        }
        .frame(width: 330)
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 8) {
            AppGlyph(size: 20, shadow: false)
            Text(appName).font(.system(size: 13, weight: .semibold))
            if case .ready(_, let plan?) = e.account {
                Text(plan.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Theme.accent.opacity(0.13)))
            }
            Spacer()
            moreMenu
        }
    }

    var moreMenu: some View {
        Menu {
            Toggle("Open at Login", isOn: Binding(get: { e.launchAtLogin }, set: { e.setLaunchAtLogin($0) }))
            Button("Refresh Now") { e.refresh() }
                .keyboardShortcut("r")
                .disabled(!e.account.isReady || e.refreshing)
            Divider()
            Button("Setup Guide…", action: actions.openSetup)
            if e.cloud == .on {
                Button("Manage Cloud Schedule…") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/code/routines")!)
                }
            }
            Button("About \(appName)", action: actions.openAbout)
            Divider()
            Button("Uninstall…", action: actions.uninstall)
            Button("Quit \(appName)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Hero

    @ViewBuilder var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let r = e.remaining, let start = e.windowStart, let end = e.windowEnd {
                HStack {
                    SectionLabel("Resets in")
                    Spacer()
                    HStack(spacing: 5) {
                        Dot(color: Theme.green)
                        Text("Window active").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                countdown(r)
                    .padding(.top, 4)
                Text("Resets at \(Fmt.time(end))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                WindowTimeline(elapsed: e.elapsedFraction, start: start, end: end, showNext: e.autoStart)
                    .padding(.top, 16)
            } else if e.starting {
                SectionLabel("Session")
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Starting a window…").font(Theme.rounded(26))
                }
                .padding(.top, 6)
                Text("This takes a few seconds.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 4)
                WindowTimeline(elapsed: nil, start: nil, end: nil, showNext: false)
                    .padding(.top, 16)
            } else if e.updated == nil {
                SectionLabel("Session")
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading usage…").font(Theme.rounded(26)).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                WindowTimeline(elapsed: nil, start: nil, end: nil, showNext: false)
                    .padding(.top, 18)
            } else {
                HStack {
                    SectionLabel("Session")
                    Spacer()
                    HStack(spacing: 5) {
                        Dot(color: Theme.accent)
                        Text("Ready").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Text("Full allowance")
                    .font(Theme.rounded(30))
                    .padding(.top, 4)
                Text(e.autoStart ? "Your next window starts automatically." : "Your next message starts a 5-hour window.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                WindowTimeline(elapsed: nil, start: nil, end: nil, showNext: false)
                    .padding(.top, 16)
                if !e.autoStart {
                    Button(action: { e.startWindow() }) {
                        Label("Start Window Now", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 14)
                }
            }
        }
    }

    func countdown(_ r: TimeInterval) -> some View {
        let (h, m) = Fmt.hm(r)
        let big = Theme.rounded(40)
        let unit = Theme.rounded(20, .medium)
        var t = Text("")
        if h > 0 {
            t = Text("\(h)").font(big) + Text("h ").font(unit).foregroundColor(.secondary)
        }
        t = t + Text(h > 0 ? String(format: "%02d", m) : "\(m)").font(big) + Text("m").font(unit).foregroundColor(.secondary)
        return t.monospacedDigit().contentTransition(.numericText()).animation(.default, value: m)
    }

    // MARK: Usage

    var usage: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Usage")
            Surface {
                VStack(spacing: 12) {
                    UsageRow(title: "Current session", detail: nil, value: e.sessionUtil)
                    UsageRow(title: "This week", detail: e.usage.weekReset.map { "Resets \(Fmt.dayTime($0, now: e.now))" },
                             value: e.weekUtil)
                }
            }
        }
    }

    // MARK: Auto-start

    var autoStart: some View {
        Surface(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 11) {
                    IconTile(symbol: "arrow.triangle.2.circlepath")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-start").font(.system(size: 13, weight: .semibold))
                        Text("Begin the next window as soon as this one ends.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(get: { e.autoStart }, set: { e.setAutoStart($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.accent)
                        .disabled(e.cloud == .checking || !e.account.isReady)
                        .padding(.top, 2)
                }
                .padding(12)
                if e.autoStart || e.cloud != .off {
                    Hairline().padding(.leading, 51)
                    CloudStatus(e: e)
                        .padding(.leading, 51)
                        .padding(.trailing, 12)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    func noticeView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5))
    }

    // MARK: Setup needed

    var setupNeeded: some View {
        let (symbol, title, text): (String, String, String) = {
            switch e.account {
            case .missing: return ("terminal", "Claude Code not found", "\(appName) works through Claude Code. Install it to continue.")
            case .signedOut: return ("person.crop.circle.badge.exclamationmark", "Sign in to Claude", "Claude Code isn't signed in to your Claude account.")
            case .apiKey: return ("creditcard", "Claude plan needed", "Claude Code is using an API key. Sign in with your Pro, Max or Team account.")
            default: return ("hourglass", "Checking Claude Code…", "One moment.")
            }
        }()
        return VStack(spacing: 10) {
            IconTile(symbol: symbol, size: 44)
                .padding(.top, 10)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if e.account != .checking {
                Button("Continue Setup", action: actions.openSetup)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            } else {
                ProgressView().controlSize(.small).padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    var footer: some View {
        HStack {
            if let u = e.updated, e.account.isReady {
                Text(e.refreshing ? "Updating…" : Fmt.ago(u, now: e.now))
            } else {
                Text(" ")
            }
            Spacer()
            Button(action: { e.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(e.refreshing ? 360 : 0))
                    .animation(e.refreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: e.refreshing)
            }
            .buttonStyle(IconButtonStyle())
            .disabled(!e.account.isReady || e.refreshing)
            .help("Refresh")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Pieces

struct UsageRow: View {
    var title: String
    var detail: String?
    var value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(Fmt.percent(value))
                    .font(Theme.rounded(12.5))
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? .tertiary : .primary)
            }
            Meter(value: value)
        }
    }
}

/// The 5-hour window as a track: elapsed, "now", the reset, and the queued next window.
struct WindowTimeline: View {
    var elapsed: Double?
    var start: Date?
    var end: Date?
    var showNext: Bool

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { g in
                let gap: CGFloat = 5
                let curW = showNext ? g.size.width * 0.74 : g.size.width
                let nextW = g.size.width - curW - gap
                let h: CGFloat = 8
                ZStack(alignment: .leading) {
                    if let p = elapsed {
                        Capsule().fill(Theme.accent.opacity(0.16)).frame(width: curW, height: h)
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.accentLight, Theme.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(h, curW * p), height: h)
                        Circle()
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                            .offset(x: min(curW - 14, max(0, curW * p - 7)))
                        if showNext {
                            Capsule()
                                .strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                                .background(Capsule().fill(Theme.accent.opacity(0.06)))
                                .frame(width: nextW, height: h)
                                .offset(x: curW + gap)
                        }
                    } else {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                            .frame(width: g.size.width, height: h)
                    }
                }
                .frame(height: 14)
            }
            .frame(height: 14)

            GeometryReader { g in
                let curW = showNext ? g.size.width * 0.74 : g.size.width
                HStack(spacing: 0) {
                    HStack {
                        Text(start.map { "Started \(Fmt.time($0))" } ?? "Now")
                        Spacer()
                        if end == nil { Text("+5 hours") }
                    }
                    .frame(width: curW)
                    if showNext {
                        Text("Next")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .foregroundStyle(Theme.accent.opacity(0.85))
                    }
                }
            }
            .frame(height: 13)
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
    }
}

/// One line under the auto-start switch saying how it's running.
struct CloudStatus: View {
    @ObservedObject var e: Engine
    var compact = true

    var body: some View {
        switch e.cloud {
        case .checking:
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text("Checking your Claude account…").foregroundStyle(.secondary)
            }
            .font(.system(size: 11.5))
        case .awaiting(let enable):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(Theme.accent)
                    Text(enable ? "Approve the request in Terminal" : "Approve in Terminal to turn off")
                        .fontWeight(.semibold)
                }
                Text(enable ? "One approval lets auto-start keep working while your Mac is closed."
                            : "This switches off the hourly schedule on your account.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("Open Terminal") { e.reopenApproval() }.buttonStyle(TextLinkStyle())
                    Button("I've Approved It") { e.checkApprovalNow() }.buttonStyle(TextLinkStyle())
                }
                .padding(.top, 1)
            }
            .font(.system(size: 11.5))
        case .on:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                Text("Works even when your Mac is closed").foregroundStyle(.secondary)
            }
            .font(.system(size: 11.5, weight: .medium))
        case .failed(let why):
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.amber)
                    Text("Only while this Mac is awake").fontWeight(.semibold)
                }
                Text(why).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Enable Closed-Lid Mode") { e.enableCloud() }.buttonStyle(TextLinkStyle())
            }
            .font(.system(size: 11.5))
        case .off:
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").foregroundStyle(Theme.accent)
                Text("On while this Mac is awake").foregroundStyle(.secondary)
            }
            .font(.system(size: 11.5, weight: .medium))
        }
    }
}
