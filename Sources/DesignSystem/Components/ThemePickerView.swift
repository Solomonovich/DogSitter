import SwiftUI

/// Runtime appearance picker — palette presets + light/dark toggle.
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
            // MARK: Palette
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

            // MARK: Light / Dark
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
    }
}
