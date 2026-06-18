import SwiftUI

/// Styles a Text as a section header (headline weight, secondary color, start-aligned).
/// Under the app's RTL environment, `.leading` renders on the right (correct for Hebrew).
struct SectionHeaderModifier: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .font(theme.typography.headline)
            .foregroundStyle(theme.color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func sectionHeader() -> some View {
        modifier(SectionHeaderModifier())
    }
}
