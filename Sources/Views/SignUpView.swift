import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedRole: UserRole = .sitter
    @State private var errorMessage = ""
    @State private var isLoading = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            BrandGradient()

            ScrollView {
                VStack(spacing: theme.spacing.xl) {
                    VStack(spacing: theme.spacing.sm) {
                        Text("הרשמה")
                            .font(theme.typography.display)
                            .foregroundStyle(theme.color.accent)

                        Text("הצטרף למשפחת דוגסיטר")
                            .font(theme.typography.headline)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    .padding(.top, theme.spacing.xl)
                    .padding(.bottom, theme.spacing.xs)

                    VStack(spacing: theme.spacing.md) {
                        ThemedInputField(icon: "person.fill", placeholder: "שם מלא", text: $fullName,
                                         textContentType: .name)
                        ThemedInputField(icon: "envelope.fill", placeholder: "אימייל", text: $email,
                                         keyboard: .emailAddress, textContentType: .emailAddress)
                        ThemedInputField(icon: "lock.fill", placeholder: "סיסמה (לפחות 6 תווים)", text: $password,
                                         isSecure: true, textContentType: .newPassword)
                        ThemedInputField(icon: "lock.fill", placeholder: "אימות סיסמה", text: $confirmPassword,
                                         isSecure: true, textContentType: .newPassword)

                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            Text("בחר את התפקיד שלך:")
                                .sectionHeader()

                            Picker("תפקיד", selection: $selectedRole) {
                                Text("אני מטפל").tag(UserRole.sitter)
                                Text("אני בעל כלב").tag(UserRole.owner)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    .padding(.horizontal, theme.spacing.xl)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(theme.color.error)
                            .font(theme.typography.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button("הירשם", action: handleSignUp)
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, theme.spacing.xl)
                        .disabled(isLoading)

                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("כבר יש לך חשבון? התחבר כאן")
                            .foregroundStyle(theme.color.accent)
                            .font(theme.typography.subheadline)
                    }
                    .padding(.top, theme.spacing.xs)

                    SocialAuthButtonsView(isLoading: $isLoading)

                    Spacer()
                }
            }
        }
        .loadingOverlay(isLoading, size: 100)
        .environment(\.layoutDirection, .rightToLeft)
        .navigationBarHidden(true)
        .swipeToGoBack { presentationMode.wrappedValue.dismiss() }
    }
    
    private func handleSignUp() {
        guard !fullName.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "אנא מלא את כל השדות."
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "הסיסמה חייבת להכיל לפחות 6 תווים."
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "הסיסמאות אינן תואמות."
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Auth.auth().createUser(withEmail: email, password: password) { result, err in
            if let err = err {
                self.isLoading = false
                self.errorMessage = AuthErrorHandler.handle(error: err)
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
                        self.errorMessage = "שגיאה ביצירת הפרופיל. אנא נסה שוב."
                    }
                }
            }
        }
    }
}

// CustomTextField replaced by ThemedInputField (Sources/DesignSystem/Modifiers/ThemedTextFieldStyle.swift)
