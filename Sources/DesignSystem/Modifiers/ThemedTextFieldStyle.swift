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
///
/// Reacts to focus: the leading icon tints to the accent colour and an accent
/// ring animates in. Secure fields get a reveal (eye) toggle. Screens that want
/// return-key field-to-field progression pass an external `focus` binding + a
/// `fieldID`; screens that don't get a self-contained ring for free.
struct ThemedInputField: View {
    @Environment(\.theme) private var theme

    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil

    // Optional external focus coordination (for `.submitLabel(.next)` chains).
    var focus: FocusState<AnyHashable?>.Binding? = nil
    var fieldID: AnyHashable? = nil
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil

    // Fallback focus when no external binding is supplied — still drives the ring.
    @FocusState private var localFocus: Bool
    @State private var isRevealed = false

    private var isActive: Bool {
        if let focus, let fieldID { return focus.wrappedValue == fieldID }
        return localFocus
    }

    private var obscure: Bool { isSecure && !isRevealed }

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(isActive ? theme.color.accent : theme.color.textSecondary)
                .frame(width: 22)

            field
                .foregroundStyle(theme.color.textPrimary)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }

            if isSecure {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(theme.color.textSecondary)
                        .frame(width: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(theme.spacing.md)
        .background(theme.color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                .stroke(theme.color.accent, lineWidth: 1.5)
                .opacity(isActive ? 1 : 0)
        )
        .animation(.easeOut(duration: 0.18), value: isActive)
    }

    @ViewBuilder
    private var input: some View {
        if obscure {
            SecureField(placeholder, text: $text)
                .textContentType(textContentType)
        } else {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textContentType(textContentType)
        }
    }

    @ViewBuilder
    private var field: some View {
        if let focus, let fieldID {
            input.focused(focus, equals: fieldID)
        } else {
            input.focused($localFocus)
        }
    }
}
