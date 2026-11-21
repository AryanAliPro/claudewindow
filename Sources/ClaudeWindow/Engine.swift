import AppKit
import ServiceManagement
import SwiftUI

enum Account: Equatable {
    case checking
    case missing                 // Claude Code CLI not installed
    case signedOut
    case apiKey                  // signed in with an API key, not a Claude plan
    case ready(email: String?, plan: String?)

    var isReady: Bool { if case .ready = self { return true } else { return false } }
}

enum CloudState: Equatable {
    case off
    case checking
    case awaiting(enable: Bool)  // waiting for the user to approve in Terminal
    case on
    case failed(String)

    var stored: String {
        switch self {
        case .on, .awaiting(enable: false): return "on"
        case .off, .checking, .awaiting(enable: true): return "off"
        case .failed(let m): return "failed:\(m)"
        }
    }

    init(stored: String?) {
        guard let s = stored else { self = .off; return }
        if s == "on" { self = .on } else if s.hasPrefix("failed:") { self = .failed(String(s.dropFirst(7))) } else { self = .off }
    }
}

/// All app state and side effects. Views observe it; the menu bar item reads it.
final class Engine: ObservableObject {
    @Published var now = Date()
    @Published var account: Account = .checking
    @Published var usage = Usage()
    @Published var updated: Date?
    @Published var refreshing = false
    @Published var starting = false
    @Published var autoStart = false
    @Published var cloud: CloudState = .off
    @Published var notice: String?
    @Published var launchAtLogin = false

    var onChange: (() -> Void)?
    var mock = false
    var claudePath: String?
    private var lastStartAttempt = Date.distantPast
    private var timer: Timer?

    // MARK: Derived

    var windowEnd: Date? { usage.sessionReset.flatMap { $0 > now ? $0 : nil } }
    var windowStart: Date? { windowEnd.map { $0.addingTimeInterval(-windowLength) } }
    var remaining: TimeInterval? { windowEnd.map { $0.timeIntervalSince(now) } }
    var hasWindow: Bool { windowEnd != nil }
    var sessionUtil: Double? { hasWindow ? usage.sessionUtil : (updated == nil ? nil : 0) }
    var weekUtil: Double? { usage.weekReset.map { $0 > now } == false ? 0 : usage.weekUtil }
    var elapsedFraction: Double {
        guard let r = remaining else { return 0 }
        return min(1, max(0, 1 - r / windowLength))
    }

    // MARK: Lifecycle

    func load() {
        autoStart = defaults.bool(forKey: Key.autoStart)
        cloud = CloudState(stored: defaults.string(forKey: Key.cloud))
        usage = Usage(sessionUtil: defaults.object(forKey: Key.sessionUtil) as? Double,
                      sessionReset: defaults.object(forKey: Key.sessionReset) as? Date,
                      weekUtil: defaults.object(forKey: Key.weekUtil) as? Double,
                      weekReset: defaults.object(forKey: Key.weekReset) as? Date)
        updated = defaults.object(forKey: Key.updated) as? Date
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start() {
        load()
        checkAccount()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self?.tick(forceRefresh: true) }
        }
    }

    private func changed() {
        onChange?()
    }

    func tick(forceRefresh: Bool = false) {
        now = Date()
        defer { changed() }
        guard account.isReady, !mock else { return }
        let stale = updated.map { now.timeIntervalSince($0) > 300 } ?? true
        let justReset = usage.sessionReset.map { $0 <= now && (updated ?? .distantPast) < $0.addingTimeInterval(20) } ?? false
        if (forceRefresh || stale || justReset) && !refreshing {
            refresh()
        }
    }

    /// Called when the menu bar panel opens.
    func panelOpened() {
        now = Date()
        if !account.isReady { checkAccount(); return }
        if updated.map({ now.timeIntervalSince($0) > 30 }) ?? true { refresh() }
    }

    // MARK: Account

    func checkAccount(then: (() -> Void)? = nil) {
        guard !mock else { then?(); return }
        if account != .checking && !account.isReady { account = .checking; changed() }
        DispatchQueue.global(qos: .utility).async {
            let path = findClaude()
            DispatchQueue.main.async {
                self.claudePath = path
                guard let path else { self.account = .missing; self.changed(); then?(); return }
                runProcess(path, ["auth", "status"], timeout: 30) { _, out in
                    let wasReady = self.account.isReady
                    if let data = out.data(using: .utf8),
                       let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if o["loggedIn"] as? Bool != true { self.account = .signedOut }
                        else if (o["authMethod"] as? String) != "claude.ai" { self.account = .apiKey }
                        else { self.account = .ready(email: o["email"] as? String, plan: Fmt.plan(o["subscriptionType"] as? String)) }
                    } else {
                        // Older CLI without `auth status`: assume signed in; a refresh will tell.
                        self.account = .ready(email: nil, plan: nil)
                    }
                    self.changed()
                    if self.account.isReady && !wasReady { self.tick(forceRefresh: true) }
                    then?()
                }
            }
        }
    }

    /// Opens Terminal running `claude auth login`.
    func signIn() {
        guard let path = claudePath ?? findClaude() else { return }
        openTerminalScript(named: "Sign in to Claude", body: """
        #!/bin/zsh
        clear
        echo "Sign in to Claude"
        echo "-----------------"
        echo "Choose your Claude account (Pro, Max or Team) when asked."
        echo
        "\(path)" auth login
        echo
        echo "Done. You can close this window and return to \(appName)."
        """)
    }

    func installClaudeCode() {
        NSWorkspace.shared.open(URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!)
    }

    private func openTerminalScript(named name: String, body: String) {
        let script = supportDir.appendingPathComponent("\(name).command")
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
    }

    // MARK: Usage

    /// Reads current usage with Claude Code's `/usage` command. No model call, no allowance used.
    private var refreshWaiters: [() -> Void] = []

    func refresh(then: (() -> Void)? = nil) {
        if refreshing { if let then { refreshWaiters.append(then) }; return }
        guard !mock, let path = claudePath else { then?(); return }
        refreshing = true
        changed()
        runProcess(path, ["-p", "/usage", "--output-format", "json"] + quietFlags, timeout: 60) { _, out in
            self.refreshing = false
            var text = out
            if let data = out.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let r = o["result"] as? String { text = r }
            if let u = parseUsage(text) {
                self.store(u)
                self.notice = nil
            } else if self.looksSignedOut(out) {
                self.account = .signedOut
            } else if text.lowercased().contains("api usage") || text.lowercased().contains("api key") {
                self.account = .apiKey
            } else {
                self.notice = "Couldn't read your usage. Retrying soon."
            }
            self.now = Date()
            self.changed()
            self.maybeAutoStart()
            then?()
            let waiters = self.refreshWaiters
            self.refreshWaiters = []
            waiters.forEach { $0() }
        }
    }

    private func store(_ u: Usage) {
        usage = u
        updated = Date()
        defaults.set(u.sessionUtil, forKey: Key.sessionUtil)
        defaults.set(u.sessionReset, forKey: Key.sessionReset)
        defaults.set(u.weekUtil, forKey: Key.weekUtil)
        defaults.set(u.weekReset, forKey: Key.weekReset)
        defaults.set(updated, forKey: Key.updated)
    }

    private func looksSignedOut(_ out: String) -> Bool {
        let low = out.lowercased()
        return low.contains("authenticate") || low.contains("oauth") || low.contains("/login") || low.contains("not logged in")
    }

    // MARK: Starting a window

    private func maybeAutoStart() {
        guard autoStart, account.isReady, !hasWindow, !starting, updated != nil,
              now.timeIntervalSince(lastStartAttempt) > 300 else { return }
        startWindow()
    }

    /// Sends one tiny message so a new 5-hour window begins now.
    func startWindow() {
        guard !mock, !starting, let path = claudePath else { return }
        starting = true
        lastStartAttempt = Date()
        changed()
        let args = ["-p", "Reply with just: ok", "--model", "haiku", "--system-prompt", "Reply with just: ok",
                    "--output-format", "stream-json", "--verbose", "--disable-slash-commands"] + quietFlags
        runProcess(path, args, timeout: 90) { status, out in
            self.starting = false
            if var u = parseRateLimitEvent(out) {
                // The event has no weekly reset on some plans; keep what /usage told us.
                if u.weekUtil == nil { u.weekUtil = self.usage.weekUtil; u.weekReset = self.usage.weekReset }
                self.store(u)
                self.notice = nil
            } else if self.looksSignedOut(out) {
                self.account = .signedOut
            } else if out.lowercased().contains("limit") {
                self.notice = "You've hit your weekly limit. Auto-start resumes after it resets."
            } else {
                self.notice = "Couldn't start a window (code \(status)). Will retry."
            }
            self.now = Date()
            self.changed()
        }
    }

    // MARK: Auto-start

    func setAutoStart(_ on: Bool) {
        autoStart = on
        defaults.set(on, forKey: Key.autoStart)
        notice = nil
        if on {
            lastStartAttempt = .distantPast
            enableCloud()
            refresh()
        } else {
            disableCloud()
        }
        changed()
    }

    private func setCloud(_ s: CloudState) {
        cloud = s
        defaults.set(s.stored, forKey: Key.cloud)
        changed()
    }

    // The closed-lid schedule lives on the user's Claude account. Reading it is
    // silent. Creating or changing it always needs the account owner's approval
    // (Claude Code enforces that), so those steps open Terminal, where the user
    // approves one request.

    private struct Remote { var id: String?; var enabled = false; var hourly = false; var env: String? }

    private func cloudResult(_ out: String) -> [String: Any]? {
        guard let r = out.range(of: "CLAUDEWINDOW_RESULT", options: .backwards) else { return nil }
        let tail = out[r.upperBound...]
        guard let a = tail.firstIndex(of: "{"), let b = tail.lastIndex(of: "}"), a < b,
              let data = String(tail[a...b]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Looks up our schedule and the first cloud environment. Read-only.
    private func lookup(done: @escaping (Remote?) -> Void) {
        guard let path = claudePath else { done(nil); return }
        let prompt = """
        /schedule You are being run non-interactively by the \(appName) app. Never ask questions. Do not create or change anything. Do exactly this:
        1. Call RemoteTrigger with {"action":"list"}.
        2. Print exactly one line and nothing after it: CLAUDEWINDOW_RESULT {"ok":true,"id":<id of the routine named exactly "\(routineName)" as a string, or null>,"enabled":<its enabled flag, or false>,"cron":<its cron_expression as a string, or null>,"environment_id":<id of the first available environment listed in your instructions as a string, or null>}
        If the list call fails, print: CLAUDEWINDOW_RESULT {"ok":false,"error":"<reason in under 12 words>"}
        """
        runProcess(path, ["-p", prompt, "--model", "haiku", "--allowedTools", "RemoteTrigger,ToolSearch,Skill",
                          "--no-session-persistence"], timeout: 150) { _, out in
            guard let r = self.cloudResult(out), r["ok"] as? Bool == true else { done(nil); return }
            done(Remote(id: r["id"] as? String, enabled: r["enabled"] as? Bool ?? false,
                        hourly: isHourly(r["cron"] as? String), env: r["environment_id"] as? String))
        }
    }

    private var pendingRequest: (intro: String, request: String)?
    private var pollGeneration = 0

    /// Opens Terminal with one request for the user to approve.
    func askApproval(intro: String, request: String, open: Bool = true) {
        guard let path = claudePath else { return }
        let prompt = """
        You were opened by the \(appName) app to finish one step that needs the account owner's approval. Do exactly this and nothing else: call the RemoteTrigger tool (load it first with ToolSearch "select:RemoteTrigger" if needed) with \(request)
        When it succeeds, reply only: "All set. You can close this window and go back to \(appName)." If it fails, explain why in one sentence.
        """
        let promptFile = supportDir.appendingPathComponent("approval-request.txt")
        try? prompt.write(to: promptFile, atomically: true, encoding: .utf8)
        let body = """
        #!/bin/zsh
        clear
        cd "\(supportDir.path)"
        echo "\(appName) needs your OK"
        echo "------------------------"
        echo "\(intro)"
        echo
        echo "Claude Code will show one request. Choose Yes to approve it."
        echo
        "\(path)" --model sonnet "$(cat "\(promptFile.path)")"
        """
        if open { openTerminalScript(named: "\(appName) Setup", body: body) }
    }

    func reopenApproval() {
        if let p = pendingRequest { askApproval(intro: p.intro, request: p.request) }
    }

    /// After asking for approval, checks a few times whether it went through.
    private func pollApproval(enable: Bool, attempt: Int = 0, generation: Int? = nil) {
        let delays: [TimeInterval] = [20, 25, 30, 45, 60, 90, 120]
        let gen = generation ?? { pollGeneration += 1; return pollGeneration }()
        guard attempt < delays.count else {
            if gen == pollGeneration, cloud == .awaiting(enable: enable) {
                if enable {
                    setCloud(.failed("The request wasn't approved."))
                } else {
                    autoStart = true
                    defaults.set(true, forKey: Key.autoStart)
                    setCloud(.on)
                    notice = "Auto-start is still on in the cloud. Switch it off again to finish."
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) {
            guard gen == self.pollGeneration, self.cloud == .awaiting(enable: enable) else { return }
            self.lookup { r in
                guard gen == self.pollGeneration, self.cloud == .awaiting(enable: enable) else { return }
                if let r, r.id != nil, r.enabled == enable, !enable || r.hourly {
                    self.setCloud(enable ? .on : .off)
                } else {
                    self.pollApproval(enable: enable, attempt: attempt + 1, generation: gen)
                }
            }
        }
    }

    func checkApprovalNow() {
        guard case .awaiting(let enable) = cloud else { return }
        lookup { r in
            if let r, r.id != nil, r.enabled == enable, !enable || r.hourly { self.setCloud(enable ? .on : .off) }
        }
    }

    /// Turns on the closed-lid schedule: reuses ours if it exists, otherwise asks to create it.
    func enableCloud() {
        guard !mock else { return }
        guard claudePath != nil else { setCloud(.failed("Claude Code isn't set up yet.")); return }
        setCloud(.checking)
        lookup { r in
            guard self.autoStart else { return }   // switched off meanwhile
            guard let r else { self.setCloud(.failed("Couldn't reach your Claude account.")); return }
            if r.id != nil, r.enabled, r.hourly { self.setCloud(.on); return }
            let request: String
            if let id = r.id {
                request = "action \"update\", trigger_id \"\(id)\", and body {\"enabled\": true, \"cron_expression\": \"0 * * * *\"}."
            } else {
                guard let env = r.env else {
                    self.setCloud(.failed("Open claude.ai/code once to finish setting up your account, then try again."))
                    return
                }
                let body: [String: Any] = [
                    "name": routineName,
                    "cron_expression": "0 * * * *",
                    "enabled": true,
                    "clear_mcp_connections": true,
                    "job_config": ["ccr": [
                        "environment_id": env,
                        "session_context": ["model": cloudModel, "sources": [String](), "allowed_tools": [String]()],
                        "events": [["data": [
                            "uuid": UUID().uuidString.lowercased(), "session_id": "", "type": "user",
                            "parent_tool_use_id": NSNull(),
                            "message": ["role": "user", "content": "Reply with just: ok. Do not use any tools."],
                        ] as [String: Any]]],
                    ] as [String: Any]],
                ]
                let json = String(data: try! JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
                request = "action \"create\" and this exact body: \(json)"
            }
            self.pendingRequest = (
                "This adds a small hourly schedule to your Claude account. Each run sends a one-word message, so your next 5-hour window starts on time even when your Mac is closed.",
                request)
            self.setCloud(.awaiting(enable: true))
            self.reopenApproval()
            self.pollApproval(enable: true)
        }
    }

    func disableCloud() {
        guard !mock else { return }
        pollGeneration += 1
        guard claudePath != nil, cloud == .on || cloud == .awaiting(enable: false) else { setCloud(.off); return }
        setCloud(.checking)
        lookup { r in
            guard !self.autoStart else { return }   // switched back on meanwhile
            guard let r else {
                self.autoStart = true
                defaults.set(true, forKey: Key.autoStart)
                self.setCloud(.on)
                self.notice = "Couldn't turn auto-start off. Check your connection and try again."
                return
            }
            guard let id = r.id, r.enabled else { self.setCloud(.off); return }
            self.pendingRequest = (
                "This switches off the hourly schedule \(appName) added to your Claude account.",
                "action \"update\", trigger_id \"\(id)\", and body {\"enabled\": false}.")
            self.setCloud(.awaiting(enable: false))
            self.reopenApproval()
            self.pollApproval(enable: false)
        }
    }

    // MARK: Login item

    func setLaunchAtLogin(_ on: Bool) {
        guard !mock else { launchAtLogin = on; return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            notice = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        changed()
    }

    // MARK: Uninstall

    /// Removes the login item and all local data. The app bundle itself is moved to the Trash by the caller.
    func removeLocalData() {
        try? SMAppService.mainApp.unregister()
        if let id = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: id) }
        try? fm.removeItem(at: supportDir)
    }
}
