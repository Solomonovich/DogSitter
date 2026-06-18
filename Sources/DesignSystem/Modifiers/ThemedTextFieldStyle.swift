import SwiftUI

/// A plain themed text field background (use on TextField/SecureField via `.textFieldStyle(...)`).
struct ThemedTextFieldStyle: TextFieldStyle {
    @Environment(\.theme) private var theme
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(theme.spacing.md)
            .background(theme.color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
    }
}

/// Reusable icon + input row. Drop-in replacement for the old `CustomTextField`.
struct ThemedInputField: View {
    @Environment(\.theme) private var theme
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(theme.color.textSecondary)
                .frame(width: 22)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textContentType(textContentType)
                }
            }
            .foregroundStyle(theme.color.textPrimary)
        }
        .padding(theme.spacing.md)
        .background(theme.color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
    }
}
