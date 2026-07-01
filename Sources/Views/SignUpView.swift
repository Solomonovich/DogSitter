import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @Environment(\.presentationMode) var presentationMode

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedRole: UserRole = .sitter
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var appeared = false

    @FocusState private var focusedField: AnyHashable?
    private enum Field: Hashable { case fullName, email, password, confirm }

    var body: some View {
        ZStack {
            BrandGradient()

            ScrollView {
                VStack(spacing: theme.spacing.xl) {
                    BrandHeader(title: "הרשמה", subtitle: "הצטרף למשפחת דוגסיטר")
                        .padding(.top, theme.spacing.xl)
                        .scaleEffect(appeared ? 1 : 0.94)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: theme.spacing.md) {
                        ThemedInputField(icon: "person.fill", placeholder: "שם מלא", text: $fullName,
                                         textContentType: .name,
                                         focus: $focusedField, fieldID: Field.fullName,
                                         submitLabel: .next,
                                         onSubmit: { focusedField = Field.email })

                        ThemedInputField(icon: "envelope.fill", placeholder: "אימייל", text: $email,
                                         keyboard: .emailAddress, textContentType: .emailAddress,
                                         focus: $focusedField, fieldID: Field.email,
                                         submitLabel: .next,
                                         onSubmit: { focusedField = Field.password })

                        ThemedInputField(icon: "lock.fill", placeholder: "סיסמה (לפחות 6 תווים)", text: $password,
                                         isSecure: true, textContentType: .newPassword,
                                         focus: $focusedField, fieldID: Field.password,
                                         submitLabel: .next,
                                         onSubmit: { focusedField = Field.confirm })

                        ThemedInputField(icon: "lock.fill", placeholder: "אימות סיסמה", text: $confirmPassword,
                                         isSecure: true, textContentType: .newPassword,
                                         focus: $focusedField, fieldID: Field.confirm,
                                         submitLabel: .go,
                                         onSubmit: submit)

                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            Text("בחר את התפקיד שלך:")
                                .sectionHeader()
                            rolePicker
                        }
                        .padding(.top, theme.spacing.xxs)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(theme.color.error)
                            .font(theme.typography.subheadline)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button("הירשם", action: submit)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isLoading)

                    signinLink

                    SocialAuthButtonsView(isLoading: $isLoading)

                    Spacer(minLength: theme.spacing.lg)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .padding(.horizontal, theme.spacing.xl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .loadingOverlay(isLoading, size: 100)
        .environment(\.layoutDirection, .rightToLeft)
        .navigationBarHidden(true)
        .swipeToGoBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            guard !appeared else { return }
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: - Role picker (themed two-pill segmented control)

    private var rolePicker: some View {
        HStack(spacing: theme.spacing.xxs) {
            rolePill(.sitter, title: "אני מטפל", icon: "pawprint.fill")
            rolePill(.owner, title: "אני בעל כלב", icon: "person.fill")
        }
        .padding(theme.spacing.xxs)
        .background(theme.color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
    }

    private func rolePill(_ role: UserRole, title: String, icon: String) -> some View {
        let selected = selectedRole == role
        return Button {
            guard selectedRole != role else { return }
            Haptics.selection()
            selectedRole = role
        } label: {
            HStack(spacing: theme.spacing.xs) {
                Image(systemName: icon)
                Text(title)
                    .font(theme.typography.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing.sm)
            .foregroundStyle(selected ? theme.color.textOnAccent : theme.color.textSecondary)
            .background {
                if selected {
                    LinearGradient(colors: theme.color.accentGradient,
                                   startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm, style: .continuous))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    private var signinLink: some View {
        Button(action: { presentationMode.wrappedValue.dismiss() }) {
            (Text("כבר יש לך חשבון? ").foregroundStyle(theme.color.textSecondary)
             + Text("התחבר כאן").foregroundStyle(theme.color.accent).fontWeight(.semibold))
                .font(theme.typography.subheadline)
        }
    }

    // MARK: - Actions

    private func submit() {
        focusedField = nil
        handleSignUp()
    }

    private func handleSignUp() {
        guard !fullName.isEmpty, !email.isEmpty, !password.isEmpty else {
            withAnimation { errorMessage = "אנא מלא את כל השדות." }
            Haptics.error()
            return
        }

        guard password.count >= 6 else {
            withAnimation { errorMessage = "הסיסמה חייבת להכיל לפחות 6 תווים." }
            Haptics.error()
            return
        }

        guard password == confirmPassword else {
            withAnimation { errorMessage = "הסיסמאות אינן תואמות." }
            Haptics.error()
            return
        }

        isLoading = true
        withAnimation { errorMessage = "" }
        Haptics.impact(.light)

        Auth.auth().createUser(withEmail: email, password: password) { result, err in
            if let err = err {
                self.isLoading = false
                withAnimation { self.errorMessage = AuthErrorHandler.handle(error: err) }
                Haptics.error()
                return
            }

            guard let uid = result?.user.uid else { return }

            // F-18: send a verification email so the user can verify before the
            // gated actions (post / express interest / start walk).
            result?.user.sendEmailVerification(completion: nil)

            // Generate clean username prefixing from email
            let username = "@" + (email.split(separator: "@").first.map(String.init) ?? "user")

            let data: [String: Any] = [
                "id": uid,
                "name": self.fullName,
                "fullName": self.fullName,
                "role": self.selectedRole.rawValue,
                "email": self.email,
                "username": username,
                "createdAt": Timestamp()
            ]

            Task {
                do {
                    try await AuthHelpers.createFirestoreUserWithRetry(uid: uid, data: data)

                    await MainActor.run {
                        self.isLoading = false
                        // Success! The AuthStateChangeListener in DogSitterApp will handle routing.
                    }
                } catch {
                    await MainActor.run {
                        self.isLoading = false
                        withAnimation { self.errorMessage = "שגיאה ביצירת הפרופיל. אנא נסה שוב." }
                        Haptics.error()
                    }
                }
            }
        }
    }
}

// CustomTextField replaced by ThemedInputField (Sources/DesignSystem/Modifiers/ThemedTextFieldStyle.swift)
