import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @Environment(\.theme) private var theme

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showSignUp = false
    @State private var appeared = false

    @FocusState private var focusedField: AnyHashable?
    private enum Field: Hashable { case email, password }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandGradient()

                ScrollView {
                    VStack(spacing: theme.spacing.xl) {
                        BrandHeader(subtitle: "האפליקציה הטובה ביותר לחיית העזר שלך")
                            .padding(.top, theme.spacing.xxl)
                            .scaleEffect(appeared ? 1 : 0.94)
                            .opacity(appeared ? 1 : 0)

                        VStack(spacing: theme.spacing.md) {
                            ThemedInputField(icon: "envelope.fill", placeholder: "אימייל", text: $email,
                                             keyboard: .emailAddress, textContentType: .emailAddress,
                                             focus: $focusedField, fieldID: Field.email,
                                             submitLabel: .next,
                                             onSubmit: { focusedField = Field.password })

                            ThemedInputField(icon: "lock.fill", placeholder: "סיסמה", text: $password,
                                             isSecure: true, textContentType: .password,
                                             focus: $focusedField, fieldID: Field.password,
                                             submitLabel: .go,
                                             onSubmit: submit)

                            HStack {
                                Button(action: resetPassword) {
                                    Text("שכחתי סיסמה")
                                        .font(theme.typography.subheadline)
                                        .foregroundStyle(theme.color.accent)
                                }
                                Spacer()
                            }

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .foregroundStyle(theme.color.error)
                                    .font(theme.typography.subheadline)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            Button("התחבר", action: submit)
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(isLoading || email.isEmpty || password.isEmpty)
                                .padding(.top, theme.spacing.xxs)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)

                        SocialAuthButtonsView(isLoading: $isLoading)
                            .opacity(appeared ? 1 : 0)

                        signupLink

                        Spacer(minLength: theme.spacing.lg)
                    }
                    .padding(.horizontal, theme.spacing.xl)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .loadingOverlay(isLoading, size: 100)
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showSignUp) { SignUpView() }
            .environment(\.layoutDirection, .rightToLeft)
            .onAppear {
                guard !appeared else { return }
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
        }
    }

    private var signupLink: some View {
        Button(action: { showSignUp = true }) {
            (Text("משתמש חדש? ").foregroundStyle(theme.color.textSecondary)
             + Text("הירשם כאן").foregroundStyle(theme.color.accent).fontWeight(.semibold))
                .font(theme.typography.subheadline)
        }
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        focusedField = nil
        handleLogin()
    }

    private func handleLogin() {
        isLoading = true
        withAnimation { errorMessage = "" }
        Haptics.impact(.light)

        Auth.auth().signIn(withEmail: email, password: password) { result, err in
            self.isLoading = false
            if let err = err {
                withAnimation { self.errorMessage = AuthErrorHandler.handle(error: err) }
                Haptics.error()
                return
            }
            // Success! AuthStateChangeListener in DogSitterApp routes context.
        }
    }

    private func resetPassword() {
        guard !email.isEmpty else {
            withAnimation { errorMessage = "אנא הזן את כתובת האימייל שלך כדי לשחזר סיסמה." }
            Haptics.error()
            return
        }

        Auth.auth().sendPasswordReset(withEmail: email) { err in
            if let err = err {
                withAnimation { self.errorMessage = AuthErrorHandler.handle(error: err) }
                Haptics.error()
            } else {
                withAnimation { self.errorMessage = "מייל לשחזור סיסמה נשלח בהצלחה." }
                Haptics.success()
            }
        }
    }
}
