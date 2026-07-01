import SwiftUI

// MARK: - Brand header

/// Shared brand lockup for the auth / onboarding flow: the app-icon logo badge,
/// the "דוגסיטר" wordmark, and an optional subtitle. Replaces the header block
/// that was previously copy-pasted into Login / SignUp / RoleSelection / Onboarding.
struct BrandHeader: View {
    @Environment(\.theme) private var theme

    var title: String = "דוגסיטר"
    var subtitle: String? = nil
    var logoSize: CGFloat = 88

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            logo
                .frame(width: logoSize, height: logoSize)
                .elevation(theme.elevation.card)

            VStack(spacing: theme.spacing.xxs) {
                Text(title)
                    .font(theme.typography.display)
                    .foregroundStyle(theme.color.textPrimary)
                    .kerning(0.5)

                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// The real app-icon mark, bundled loose at `Sources/Resources/AppLogo.png`
    /// (same loose-resource pattern as the Lottie `icon.json`). Falls back to a
    /// gradient pawprint badge so the header never renders broken.
    @ViewBuilder
    private var logo: some View {
        if let image = UIImage(named: "AppLogo") {
            // The source art has a thin white keyline around the blue tile. Scale
            // up slightly and re-clip to a clean rounded rect so that white border
            // is pushed outside the clip, leaving crisp blue edges on any background.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(1.12)
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.235, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                .fill(LinearGradient(colors: theme.color.accentGradient,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: logoSize * 0.42, weight: .bold))
                        .foregroundStyle(theme.color.textOnAccent)
                )
        }
    }
}

// MARK: - Press animation

/// Generic press feedback (scale + slight dim) matching `PrimaryButtonStyle`,
/// for buttons that supply their own fill (e.g. the social buttons).
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Social login button

/// A themed OAuth button: leading brand logo + label, full width within its
/// column, standard radius/padding, press animation and a light haptic.
struct SocialLoginButton<Logo: View>: View {
    @Environment(\.theme) private var theme

    let label: String
    let background: Color
    let foreground: Color
    var border: Color? = nil
    @ViewBuilder var logo: () -> Logo
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: theme.spacing.xs) {
                logo()
                    .frame(width: 20, height: 20)
                Text(label)
                    .font(theme.typography.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing.md)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)
                    .stroke(border ?? .clear, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Google "G" mark

/// A four-colour Google "G", drawn with arcs so no bundled Google asset is
/// required (SF Symbols has no Google glyph). Scales to its frame.
struct GoogleGMark: View {
    // Official Google brand colours.
    private let blue   = Color(red: 0.259, green: 0.522, blue: 0.957)  // #4285F4
    private let red    = Color(red: 0.918, green: 0.263, blue: 0.208)  // #EA4335
    private let yellow = Color(red: 0.984, green: 0.737, blue: 0.020)  // #FBBC05
    private let green  = Color(red: 0.204, green: 0.659, blue: 0.325)  // #34A853

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth = side * 0.24
            let radius = (side - lineWidth) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                arc(from: 315, to: 405, color: blue, center: center, radius: radius, lineWidth: lineWidth)   // right
                arc(from: 225, to: 315, color: red, center: center, radius: radius, lineWidth: lineWidth)     // top
                arc(from: 150, to: 225, color: yellow, center: center, radius: radius, lineWidth: lineWidth)  // left
                arc(from: 45,  to: 150, color: green, center: center, radius: radius, lineWidth: lineWidth)   // bottom

                // The blue crossbar of the "G", reaching in from the right toward the centre.
                Rectangle()
                    .fill(blue)
                    .frame(width: side * 0.30, height: lineWidth)
                    .position(x: center.x + side * 0.16, y: center.y)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func arc(from start: Double, to end: Double, color: Color,
                     center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> some View {
        Path { path in
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
    }
}
