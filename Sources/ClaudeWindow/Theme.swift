import SwiftUI

enum Theme {
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)      // #D97757
    static let accentLight = Color(red: 0.925, green: 0.592, blue: 0.459)  // #EC9775
    static let accentDeep = Color(red: 0.749, green: 0.353, blue: 0.231)   // #BF5A3B
    static let green = Color(red: 0.196, green: 0.663, blue: 0.392)
    static let amber = Color(red: 0.914, green: 0.584, blue: 0.157)
    static let red = Color(red: 0.890, green: 0.290, blue: 0.251)

    static let fill = Color.primary.opacity(0.045)
    static let fillStrong = Color.primary.opacity(0.075)
    static let hairline = Color.primary.opacity(0.085)

    static let accentGradient = LinearGradient(colors: [accentLight, accent, accentDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)

    static func meter(_ v: Double) -> Color { v >= 0.9 ? red : v >= 0.75 ? amber : accent }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Building blocks

struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
}

struct Meter: View {
    var value: Double?
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fillStrong)
                if let v = value, v > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.meter(v).opacity(0.8), Theme.meter(v)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(height, min(1, v) * g.size.width))
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

struct IconTile: View {
    var symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

struct Dot: View {
    var color: Color
    var size: CGFloat = 6
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

/// The app mark: a warm squircle with a countdown arc and a "next" knob.
struct AppGlyph: View {
    var size: CGFloat
    var shadow = true
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.945, green: 0.624, blue: 0.494), Theme.accent, Theme.accentDeep],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.0)],
                                             startPoint: .top, endPoint: .center), lineWidth: max(0.5, size * 0.012))
            let d = size * 0.54
            let w = size * 0.085
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: w)
                .frame(width: d, height: d)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(.white, style: StrokeStyle(lineWidth: w, lineCap: .round))
                .frame(width: d, height: d)
                .rotationEffect(.degrees(-90))
            // Knob at the end of the arc.
            Circle()
                .fill(.white)
                .frame(width: w * 1.9, height: w * 1.9)
                .shadow(color: .black.opacity(0.18), radius: size * 0.012, y: size * 0.006)
                .offset(x: d / 2)
                .rotationEffect(.degrees(-90 + 360 * 0.72))
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: .black.opacity(shadow ? 0.18 : 0), radius: size * 0.04, y: size * 0.02)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13.5 : 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 22 : 14)
            .frame(minHeight: large ? 36 : 28)
            .background(
                RoundedRectangle(cornerRadius: large ? 10 : 8, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accentLight, Theme.accent], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: large ? 10 : 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: Theme.accentDeep.opacity(enabled ? 0.25 : 0), radius: 3, y: 1)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13.5 : 12.5, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, large ? 18 : 12)
            .frame(minHeight: large ? 36 : 28)
            .background(
                RoundedRectangle(cornerRadius: large ? 10 : 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
            .contentShape(Rectangle())
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct IconButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hover ? 0.07 : 0)))
            .contentShape(Circle())
            .onHover { hover = $0 }
    }
}
