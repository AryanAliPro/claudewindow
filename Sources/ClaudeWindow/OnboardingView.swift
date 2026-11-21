import Combine
import SwiftUI

final class OnboardingFlow: ObservableObject {
    @Published var step = 0
    static let count = 4
}

/// First-run setup: welcome → connect Claude Code → auto-start → done.
struct OnboardingView: View {
    @ObservedObject var e: Engine
    @ObservedObject var flow: OnboardingFlow
    var finish: () -> Void

    private let recheck = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch flow.step {
                case 0: welcome
                case 1: connect
                case 2: autoStartStep
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 48)
            .padding(.top, 52)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(flow.step)

            Hairline()
            bottomBar
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
        }
        .frame(width: 540, height: 620)
        .background(backdrop)
        .onReceive(recheck) { _ in
            if flow.step == 1 && !e.account.isReady && e.account != .checking { e.checkAccount() }
        }
    }

    var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 360)
                .frame(height: 420)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    private func go(_ step: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { flow.step = step }
    }

    // MARK: Bottom bar

    var bottomBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<OnboardingFlow.count, id: \.self) { i in
                    Capsule()
                        .fill(i == flow.step ? Theme.accent : Color.primary.opacity(0.15))
                        .frame(width: i == flow.step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: flow.step)
            Spacer()
            if flow.step == 1 || flow.step == 2 {
                Button("Back") { go(flow.step - 1) }
                    .buttonStyle(SecondaryButtonStyle(large: true))
            }
            primaryButton
        }
    }

    @ViewBuilder var primaryButton: some View {
        switch flow.step {
        case 0:
            Button("Get Started") { go(1) }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
        case 1:
            Button("Continue") { go(2) }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!e.account.isReady)
        case 2:
            if e.autoStart {
                Button("Continue") { go(3) }
                    .buttonStyle(PrimaryButtonStyle(large: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Not Now") { go(3) }
                    .buttonStyle(QuietButtonStyle())
                Button("Turn On Auto-Start") { e.setAutoStart(true) }
                    .buttonStyle(PrimaryButtonStyle(large: true))
                    .keyboardShortcut(.defaultAction)
            }
        default:
            Button("Open \(appName)", action: finish)
                .buttonStyle(PrimaryButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Step 1 — Welcome

    var welcome: some View {
        VStack(spacing: 0) {
            AppGlyph(size: 92)
            Text(appName)
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 22)
            Text("Keep your Claude usage limit close to reset, all day long.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 18) {
                Feature(symbol: "timer", title: "Live countdown",
                        text: "See your usage and exactly when your 5-hour window resets, right in the menu bar.")
                Feature(symbol: "arrow.triangle.2.circlepath", title: "Back-to-back windows",
                        text: "A new window starts the moment the last one ends, so a reset is never far away.")
                Feature(symbol: "moon.zzz.fill", title: "Works while you're away",
                        text: "Keeps windows rolling even when your Mac is asleep or closed.")
            }
            .padding(.top, 34)
        }
    }

    // MARK: Step 2 — Connect

    var connect: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(symbol: "link", title: "Connect Claude Code",
                       text: "\(appName) works through the Claude Code app on this Mac. Your sign-in stays on this computer.")
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    ChecklistRow(state: installState, title: "Claude Code installed", detail: installDetail) {
                        if e.account == .missing {
                            Button("Install") { e.installClaudeCode() }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    Hairline().padding(.leading, 50)
                    ChecklistRow(state: signInState, title: "Signed in with a Claude plan", detail: signInDetail) {
                        if e.account == .signedOut || e.account == .apiKey {
                            Button("Sign In") { e.signIn() }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
            .padding(.top, 26)
            if !e.account.isReady && e.account != .checking {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text("Waiting… this updates on its own.")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
                .padding(.leading, 2)
            }
            Spacer()
            Text("Requires a Claude Pro, Max, Team or Enterprise plan.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 22)
        }
    }

    var installState: CheckState {
        switch e.account {
        case .checking: return .working
        case .missing: return .todo
        default: return .done
        }
    }
    var installDetail: String {
        switch e.account {
        case .checking: return "Looking for Claude Code…"
        case .missing: return "Not found on this Mac."
        default: return e.claudePath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Found"
        }
    }
    var signInState: CheckState {
        switch e.account {
        case .checking: return .working
        case .missing: return .waiting
        case .signedOut, .apiKey: return .todo
        case .ready: return .done
        }
    }
    var signInDetail: String {
        switch e.account {
        case .checking: return "Checking…"
        case .missing: return "Install Claude Code first."
        case .signedOut: return "Not signed in."
        case .apiKey: return "Signed in with an API key. Use your Claude account instead."
        case .ready(let email, let plan):
            return [email, plan.map { "\($0) plan" }].compactMap { $0 }.joined(separator: " · ").ifEmpty("Signed in")
        }
    }

    // MARK: Step 3 — Auto-start

    var autoStartStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(symbol: "arrow.triangle.2.circlepath", title: "Never wait long for a reset",
                       text: "With auto-start on, a fresh 5-hour window begins the moment the last one ends. Whenever you sit down to work, your next reset is close.")
            ChainIllustration()
                .padding(.top, 24)
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "moon.zzz.fill", title: "Keeps going when your Mac is closed",
                        text: "Adds a small hourly schedule to your Claude account. Claude Code asks you to approve it once, in Terminal.",
                        compact: true)
                Feature(symbol: "leaf.fill", title: "Uses almost none of your allowance",
                        text: "Each run sends a one-word message to Claude's smallest model.",
                        compact: true)
            }
            .padding(.top, 22)
            Spacer()
            if e.autoStart {
                Surface {
                    CloudStatus(e: e)
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: Step 4 — Done

    var done: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Theme.accentGradient).frame(width: 76, height: 76)
                    .shadow(color: Theme.accentDeep.opacity(0.35), radius: 10, y: 4)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("You're all set")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 22)
            Text("\(appName) lives in your menu bar. Click it anytime to see your usage and when your window resets.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            MenuBarMock()
                .padding(.top, 30)
            Surface {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at login").font(.system(size: 13, weight: .medium))
                        Text("Start \(appName) when you log in to your Mac.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { e.launchAtLogin }, set: { e.setLaunchAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.accent)
                }
            }
            .padding(.top, 34)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Onboarding pieces

struct StepHeader: View {
    var symbol: String
    var title: String
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconTile(symbol: symbol, size: 40)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 16)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .padding(.top, 6)
        }
    }
}

struct Feature: View {
    var symbol: String
    var title: String
    var text: String
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol, size: compact ? 30 : 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: compact ? 13 : 14, weight: .semibold))
                Text(text)
                    .font(.system(size: compact ? 12 : 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum CheckState { case working, todo, waiting, done }

struct ChecklistRow<Trailing: View>: View {
    var state: CheckState
    var title: String
    var detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                switch state {
                case .working: ProgressView().controlSize(.small)
                case .done:
                    Circle().fill(Theme.green).frame(width: 24, height: 24)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                case .todo:
                    Circle().strokeBorder(Theme.accent, lineWidth: 1.5).frame(width: 24, height: 24)
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                case .waiting:
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5).frame(width: 24, height: 24)
                }
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
    }
}

/// Three back-to-back windows across a day.
struct ChainIllustration: View {
    var body: some View {
        let cal = Calendar.current
        let base = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        let starts = (0..<3).map { base.addingTimeInterval(Double($0) * windowLength) }
        return Surface(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("A day with auto-start").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 5) {
                        Dot(color: Theme.accent)
                        Text("5-hour window").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.accentLight, Theme.accent], startPoint: .top, endPoint: .bottom))
                                .opacity(1 - Double(i) * 0.22)
                                .frame(height: 26)
                                .overlay(
                                    Text("Window \(i + 1)")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                            Text(Fmt.time(starts[i]))
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

/// A sketch of the menu bar with the app's item highlighted.
struct MenuBarMock: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Spacer()
                Image(systemName: "wifi").foregroundStyle(.secondary)
                Image(systemName: "battery.75percent").foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Image(nsImage: ringImage(progress: 0.74, height: 15))
                        .renderingMode(.template)
                    Text("3:42").font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.accent.opacity(0.18)))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
                .overlay(alignment: .bottom) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                        .offset(y: 20)
                }
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("Fri 9:41").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.fillStrong))
            Color.clear.frame(height: 16)
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
