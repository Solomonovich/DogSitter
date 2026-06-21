import SwiftUI

/// Runtime appearance picker — color palette, light/dark, and the visual
/// customization settings (text size, roundness, background & avatar).
/// Lives in the Profile screens.
struct ThemePickerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            content
                .padding(theme.spacing.md)
        }
        .screenBackground()
        .navigationTitle("מראה ותצוגה")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            paletteSection
            appearanceModeSection
            textSizeSection
            roundnessSection
            backgroundAndAvatarSection
        }
    }

    // MARK: - Palette

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("ערכת צבעים")
                .sectionHeader()

            VStack(spacing: 0) {
                ForEach(Array(ThemePalette.allCases.enumerated()), id: \.element) { index, palette in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            themeManager.palette = palette
                        }
                    } label: {
                        HStack(spacing: theme.spacing.md) {
                            Circle()
                                .fill(LinearGradient(
                                    colors: palette.accentGradient(dark: themeManager.isDarkMode),
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 28, height: 28)
                            Text(palette.displayName)
                                .font(theme.typography.body)
                                .foregroundStyle(theme.color.textPrimary)
                            Spacer()
                            if themeManager.palette == palette {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.color.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, theme.spacing.sm)
                    }
                    .buttonStyle(.plain)

                    if index < ThemePalette.allCases.count - 1 {
                        Divider().overlay(theme.color.separator)
                    }
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .card(padding: 0)
        }
    }

    // MARK: - Light / Dark

    private var appearanceModeSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("מצב תצוגה")
                .sectionHeader()
            HStack {
                Spacer()
                ThemeToggleView()
                Spacer()
            }
            .padding(.vertical, theme.spacing.sm)
            .frame(maxWidth: .infinity)
            .card()
        }
    }

    // MARK: - Text size

    private func previewSize(_ size: TextSizePreference) -> CGFloat {
        switch size {
        case .small:    return 15
        case .standard: return 19
        case .large:    return 23
        case .xLarge:   return 27
        }
    }

    private var textSizeSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("גודל טקסט")
                .sectionHeader()

            VStack(spacing: theme.spacing.md) {
                HStack(spacing: theme.spacing.xs) {
                    ForEach(TextSizePreference.allCases) { size in
                        let selected = themeManager.textSize == size
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                themeManager.textSize = size
                            }
                        } label: {
                            Text("א")
                                .font(.system(size: previewSize(size), weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, theme.spacing.sm)
                                .background(selected ? theme.color.accent : theme.color.surfaceSecondary)
                                .foregroundStyle(selected ? theme.color.textOnAccent : theme.color.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Live preview — uses the themed body font, which already reflects the scale.
                HStack {
                    Text("טקסט לדוגמה")
                        .font(theme.typography.body)
                        .foregroundStyle(theme.color.textPrimary)
                    Spacer()
                    Text(themeManager.textSize.displayName)
                        .font(theme.typography.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            .card()
        }
    }

    // MARK: - Roundness

    private var roundnessSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("עיגול פינות")
                .sectionHeader()

            VStack(spacing: 0) {
                ForEach(Array(CornerStyle.allCases.enumerated()), id: \.element) { index, style in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            themeManager.cornerStyle = style
                        }
                    } label: {
                        HStack(spacing: theme.spacing.md) {
                            RoundedRectangle(cornerRadius: style.sampleRadius, style: .continuous)
                                .fill(theme.color.surfaceSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: style.sampleRadius, style: .continuous)
                                        .strokeBorder(theme.color.accent, lineWidth: 2)
                                )
                                .frame(width: 28, height: 28)
                            Text(style.displayName)
                                .font(theme.typography.body)
                                .foregroundStyle(theme.color.textPrimary)
                            Spacer()
                            if themeManager.cornerStyle == style {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.color.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, theme.spacing.sm)
                    }
                    .buttonStyle(.plain)

                    if index < CornerStyle.allCases.count - 1 {
                        Divider().overlay(theme.color.separator)
                    }
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .card(padding: 0)
        }
    }

    // MARK: - Background & avatar

    private var backgroundAndAvatarSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("רקע ותמונת פרופיל")
                .sectionHeader()

            VStack(spacing: theme.spacing.md) {
                Toggle(isOn: Binding(
                    get: { themeManager.useGradientBackground },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            themeManager.useGradientBackground = newValue
                        }
                    }
                )) {
                    HStack(spacing: theme.spacing.sm) {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundStyle(theme.color.accent)
                        Text("רקע מדורג")
                            .font(theme.typography.body)
                            .foregroundStyle(theme.color.textPrimary)
                    }
                }
                .tint(theme.color.accent)

                Divider().overlay(theme.color.separator)

                HStack {
                    Text("צורת תמונה")
                        .font(theme.typography.body)
                        .foregroundStyle(theme.color.textPrimary)
                    Spacer()
                    HStack(spacing: theme.spacing.sm) {
                        ForEach(AvatarShape.allCases) { shape in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    themeManager.avatarShape = shape
                                }
                            } label: {
                                avatarSwatch(shape)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .card()
        }
    }

    private func avatarSwatch(_ shape: AvatarShape) -> some View {
        let selected = themeManager.avatarShape == shape
        return ZStack {
            shape.clipShape(for: 38)
                .fill(theme.color.surfaceSecondary)
                .frame(width: 38, height: 38)
            Image(systemName: "person.fill")
                .foregroundStyle(theme.color.textSecondary)
        }
        .overlay(
            shape.clipShape(for: 38)
                .stroke(selected ? theme.color.accent : theme.color.separator,
                        lineWidth: selected ? 2.5 : 1)
        )
    }
}
