import SwiftUI

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .lightClassic
}

extension EnvironmentValues {
    /// The active design theme. Read it in a view with `@Environment(\.theme) private var theme`.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Injects a theme into the environment (useful in previews and the app root).
    func theme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
    }
}
