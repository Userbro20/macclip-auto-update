import SwiftUI

enum MacClipperTheme {
    static let cyan = Color(red: 0.12, green: 0.72, blue: 0.90)
    static let ember = Color(red: 0.95, green: 0.46, blue: 0.20)
    static let sand = Color(red: 0.95, green: 0.79, blue: 0.46)
    static let success = Color(red: 0.24, green: 0.75, blue: 0.48)
}

enum MacClipperBackdropStyle {
    case atmospheric
    case menuGray
}

struct MacClipperBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    private let style: MacClipperBackdropStyle

    init(style: MacClipperBackdropStyle = .atmospheric) {
        self.style = style
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(primaryGlowColor)
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -160, y: -180)

            Circle()
                .fill(secondaryGlowColor)
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 180, y: 150)
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color] {
        switch style {
        case .menuGray:
            if colorScheme == .dark {
                return [
                    Color(red: 0.07, green: 0.08, blue: 0.09),
                    Color(red: 0.10, green: 0.11, blue: 0.12),
                    Color(red: 0.05, green: 0.05, blue: 0.06)
                ]
            }

            return [
                Color(red: 0.18, green: 0.19, blue: 0.20),
                Color(red: 0.22, green: 0.23, blue: 0.24),
                Color(red: 0.14, green: 0.15, blue: 0.16)
            ]
        case .atmospheric:
            if colorScheme == .dark {
                return [
                    Color(red: 0.06, green: 0.07, blue: 0.10),
                    Color(red: 0.09, green: 0.12, blue: 0.18),
                    Color(red: 0.16, green: 0.10, blue: 0.08)
                ]
            }

            return [
                Color(red: 0.96, green: 0.98, blue: 1.00),
                Color(red: 0.98, green: 0.95, blue: 0.92),
                Color(red: 0.92, green: 0.96, blue: 0.98)
            ]
        }
    }

    private var primaryGlowColor: Color {
        switch style {
        case .menuGray:
            return Color.white.opacity(colorScheme == .dark ? 0.05 : 0.08)
        case .atmospheric:
            return MacClipperTheme.cyan.opacity(colorScheme == .dark ? 0.22 : 0.18)
        }
    }

    private var secondaryGlowColor: Color {
        switch style {
        case .menuGray:
            return Color.black.opacity(colorScheme == .dark ? 0.30 : 0.18)
        case .atmospheric:
            return MacClipperTheme.ember.opacity(colorScheme == .dark ? 0.20 : 0.14)
        }
    }
}

struct MacClipperSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat = 24, padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                radius: colorScheme == .dark ? 18 : 12,
                y: 10
            )
    }
}

struct MacClipperPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(colorScheme == .dark ? .white : Color.black.opacity(0.82))
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.28 : 0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.44 : 0.28), lineWidth: 1)
            )
    }
}

struct MacClipperSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

struct MacClipperPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [MacClipperTheme.cyan, MacClipperTheme.ember],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: MacClipperTheme.cyan.opacity(0.24), radius: 12, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct MacClipperSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(colorScheme == .dark ? .white : Color.black.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.70))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}