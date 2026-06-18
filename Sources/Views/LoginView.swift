import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @Environment(\.layoutDirection) var layoutDirection
    @Environment(\.theme) private var theme
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showSignUp = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                BrandGradient()

                ScrollView {
                    VStack(spacing: theme.spacing.xl) {
                        VStack(spacing: theme.spacing.sm) {
                            Text("דוגסיטר")
                                .font(theme.typography.display)
                                .foregroundStyle(theme.color.accent)
                                .shadow(color: theme.color.accent.opacity(0.3), radius: 5, x: 0, y: 5)

                            Text("האפליקציה הטובה ביותר לחיית עזרך")
                                .font(theme.typography.headline)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                        .padding(.top, 60)
                        .padding(.bottom, theme.spacing.lg)

                        VStack(spacing: theme.spacing.md) {
                            ThemedInputField(icon: "envelope.fill", placeholder: "אימייל", text: $email,
                                             keyboard: .emailAddress, textContentType: .emailAddress)
                            ThemedInputField(icon: "lock.fill", placeholder: "סיסמה", text: $password,
                                             isSecure: true, textContentType: .password)
                        }
                        .padding(.horizontal, theme.spacing.xl)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundStyle(theme.color.error)
                                .font(theme.typography.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button("התחבר", action: handleLogin)
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.horizontal, theme.spacing.xl)
                            .disabled(isLoading || email.isEmpty || password.isEmpty)

                        Button(action: resetPassword) {
                            Text("שכחתי סיסמה")
                                .foregroundStyle(theme.color.accent)
                                .font(theme.typography.subheadline)
                        }

                        Button(action: { showSignUp = true }) {
                            Text("משתמש חדש? הירשם כאן")
                                .foregroundStyle(theme.color.accent)
                                .font(theme.typography.subheadline)
                        }
                        .navigationDestination(isPresented: $showSignUp) {
                            SignUpView()
                        }

                        SocialAuthButtonsView(isLoading: $isLoading)

                        Spacer()
                    }
                }
            }
            .loadingOverlay(isLoading, size: 100)
            .navigationBarHidden(true)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
    
    private func handleLogin() {
        isLoading = true
        errorMessage = ""
        
        Auth.auth().signIn(withEmail: email, password: password) { result, err in
            self.isLoading = false
            if let err = err {
                self.errorMessage = AuthErrorHandler.handle(error: err)
                return
            }
            // Success! AuthStateChangeListener in DogSitterApp routes context.
        }
    }
    
    private func resetPassword() {
        guard !email.isEmpty else {
            errorMessage = "אנא הזן את כתובת האימייל שלך כדי לשחזר סיסמה."
            return
        }
        
        Auth.auth().sendPasswordReset(withEmail: email) { err in
            if let err = err {
                self.errorMessage = AuthErrorHandler.handle(error: err)
            } else {
                self.errorMessage = "מייל לשחזור סיסמה נשלח בהצלחה."
            }
        }
    }
}
