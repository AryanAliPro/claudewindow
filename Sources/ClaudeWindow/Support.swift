import AppKit
import Foundation

// MARK: - Constants

let appName = "ClaudeWindow"
let windowLength: TimeInterval = 5 * 3600
/// Name of the hourly cloud schedule the app keeps on the user's Claude account.
let routineName = "ClaudeWindow"
/// Model the cloud schedule uses. It only ever replies "ok".
let cloudModel = "claude-haiku-5-5"

let defaults = UserDefaults.standard
let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser

let supportDir: URL = {
    let d = home.appendingPathComponent("Library/Application Support/\(appName)")
    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}()

enum Key {
    static let onboarded = "onboarded"
    static let autoStart = "autoStart"
    static let cloud = "cloudState"
    static let sessionUtil = "sessionUtil"
    static let sessionReset = "sessionReset"
    static let weekUtil = "weekUtil"
    static let weekReset = "weekReset"
    static let updated = "updated"
}

// MARK: - Claude Code CLI

func findClaude() -> String? {
    let h = home.path
    let candidates = ["\(h)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                      "\(h)/.claude/local/claude", "\(h)/.npm-global/bin/claude", "\(h)/.bun/bin/claude",
                      "\(h)/.volta/bin/claude"]
    if let c = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return c }
    // Fall back to the user's login-shell PATH (nvm, asdf, custom prefixes).
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", "command -v claude"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    p.waitUntilExit()
    return fm.isExecutableFile(atPath: out) ? out : nil
}

/// Flags that keep background CLI calls quiet and cheap: no tools, no MCP
/// servers, no user hooks or settings, nothing saved to session history.
/// (`/usage` is a slash command, so slash commands stay enabled here.)
let quietFlags = ["--strict-mcp-config", "--tools", "", "--setting-sources", "", "--no-session-persistence"]

/// Runs a process off the main thread and calls `done` on the main thread.
func runProcess(_ path: String, _ args: [String], timeout: TimeInterval,
                done: @escaping (Int32, String) -> Void) {
    DispatchQueue.global(qos: .utility).async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.currentDirectoryURL = supportDir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            DispatchQueue.main.async { done(-1, error.localizedDescription) }
            return
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        let text = String(data: data, encoding: .utf8) ?? ""
        DispatchQueue.main.async { done(p.terminationStatus, text) }
    }
}

// MARK: - Usage parsing

struct Usage: Equatable {
    var sessionUtil: Double?
    var sessionReset: Date?
    var weekUtil: Double?
    var weekReset: Date?
}

/// Parses the text of Claude Code's `/usage` command, e.g.
/// "Current session: 67% used · resets Nov 21 at 11:10pm (Asia/Karachi)".
func parseUsage(_ text: String, now: Date = Date()) -> Usage? {
    var u = Usage()
    var found = false
    for raw in text.components(separatedBy: .newlines) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("Current session") {
            found = true
            (u.sessionUtil, u.sessionReset) = parseLimitLine(line, now: now)
        } else if line.hasPrefix("Current week (all models)") || (u.weekUtil == nil && line.hasPrefix("Current week:")) {
            (u.weekUtil, u.weekReset) = parseLimitLine(line, now: now)
        }
    }
    return found ? u : nil
}

private let pctRegex = try! NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*%"#)
private let resetRegex = try! NSRegularExpression(pattern: #"resets\s+(.+?)\s*(?:\(([^)]+)\))?\s*$"#)

func parseLimitLine(_ line: String, now: Date) -> (Double?, Date?) {
    let ns = line as NSString
    var pct: Double?
    if let m = pctRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
        pct = Double(ns.substring(with: m.range(at: 1))).map { $0 / 100 }
    }
    var date: Date?
    if let m = resetRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
        let when = ns.substring(with: m.range(at: 1))
        let tz = m.range(at: 2).location != NSNotFound ? TimeZone(identifier: ns.substring(with: m.range(at: 2))) : nil
        date = parseResetTime(when, timeZone: tz ?? .current, now: now)
    }
    return (pct, date)
}

func parseResetTime(_ s: String, timeZone: TimeZone, now: Date) -> Date? {
    let text = s.lowercased()
        .replacingOccurrences(of: "\u{202F}", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timeZone
    f.amSymbol = "am"
    f.pmSymbol = "pm"
    // Missing fields (year, minutes) come from the start of today, not from `now`.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    f.defaultDate = cal.startOfDay(for: now)
    let withDate = ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d, h:mma", "MMM d, ha", "MMM d"]
    let timeOnly = ["h:mma", "ha", "h:mm a", "h a"]
    for fmt in withDate {
        f.dateFormat = fmt
        if var d = f.date(from: text) {
            // No year in the text: roll into next year if it would be in the past (Dec → Jan).
            if d < now.addingTimeInterval(-86400 * 30) {
                d = Calendar.current.date(byAdding: .year, value: 1, to: d) ?? d
            }
            return d
        }
    }
    for fmt in timeOnly {
        f.dateFormat = fmt
        if var d = f.date(from: text) {
            if d < now.addingTimeInterval(-600) { d = d.addingTimeInterval(86400) }
            return d
        }
    }
    return nil
}

/// Reads the exact window from the rate-limit event in `--output-format stream-json` output.
func parseRateLimitEvent(_ out: String) -> Usage? {
    var u = Usage()
    var found = false
    for line in out.split(separator: "\n") where line.contains("rate_limit_event") {
        guard let data = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = o["rate_limit_info"] as? [String: Any] else { continue }
        let windows = info["unifiedWindows"] as? [String: Any]
        if let five = windows?["five_hour"] as? [String: Any], let r = five["resetsAt"] as? Double {
            u.sessionReset = Date(timeIntervalSince1970: r)
            u.sessionUtil = five["utilization"] as? Double
            found = true
        } else if info["rateLimitType"] as? String == "five_hour", let r = info["resetsAt"] as? Double {
            u.sessionReset = Date(timeIntervalSince1970: r)
            found = true
        }
        if let week = windows?["seven_day"] as? [String: Any] {
            u.weekUtil = week["utilization"] as? Double
            u.weekReset = (week["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        }
    }
    return found ? u : nil
}

/// The server pins "0 * * * *" to a fixed minute, e.g. "13 * * * *".
func isHourly(_ cron: String?) -> Bool {
    guard let parts = cron?.split(separator: " "), parts.count == 5 else { return false }
    return Int(parts[0]) != nil && parts[1...].allSatisfy { $0 == "*" }
}

// MARK: - Formatting

enum Fmt {
    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func dayTime(_ d: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return time(d) }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "Tomorrow \(time(d))" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return f.string(from: d)
    }

    /// (hours, minutes) rounded up so "0m" only shows when the window has ended.
    static func hm(_ t: TimeInterval) -> (Int, Int) {
        let m = max(0, Int((t / 60).rounded(.up)))
        return (m / 60, m % 60)
    }

    static func compact(_ t: TimeInterval) -> String {
        let (h, m) = hm(t)
        return h > 0 ? String(format: "%d:%02d", h, m) : "\(m)m"
    }

    static func percent(_ v: Double?) -> String {
        v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    static func ago(_ d: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 45 { return "Updated just now" }
        let m = s / 60
        if m < 60 { return "Updated \(max(1, m)) min ago" }
        return "Updated \(m / 60) hr ago"
    }

    static func plan(_ raw: String?) -> String? {
        guard let r = raw?.lowercased(), !r.isEmpty else { return nil }
        switch r {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return r.capitalized
        }
    }
}
