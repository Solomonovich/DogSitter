import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        if !appState.isAuthenticated {
            LoginView()
        } else if appState.currentUserRole == .needsRole {
            if let currentUser = Auth.auth().currentUser {
                SocialRoleSelectionView(uid: currentUser.uid, email: currentUser.email ?? "unknown@apple.com")
            } else {
                LoginView()
            }
        } else if let user = appState.currentUser,
                  (user.phone?.isEmpty ?? true) || (user.address?.isEmpty ?? true) {
            ContactDetailsOnboardingView()
        } else if appState.currentUserRole == .none {
            VStack {
                if let errorMsg = appState.activeError {
                    Text(errorMsg)
                        .foregroundStyle(theme.color.error)
                        .multilineTextAlignment(.center)
                        .padding()

                    Button("נסה שוב") {
                        if let uid = Auth.auth().currentUser?.uid {
                            Task {
                                await appState.fetchCurrentProfile(uid: uid)
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                } else {
                    LottieProgressView(size: 100)
                    Text("טוען פרופיל...")
                        .foregroundStyle(theme.color.textSecondary)
                        .padding(.top, theme.spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
        } else {
            MainTabView()
        }
    }
}

struct ContactDetailsOnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    var isValid: Bool {
        phone.count >= 9 && !address.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                BrandGradient()

                ScrollView {
                    VStack(spacing: theme.spacing.lg) {
                        VStack(spacing: theme.spacing.xs) {
                            Text("דוגסיטר")
                                .font(theme.typography.display)
                                .foregroundStyle(theme.color.accent)
                                .shadow(color: theme.color.accent.opacity(0.3), radius: 5, x: 0, y: 5)

                            Text("פרטי יצירת קשר")
                                .font(theme.typography.title2)
                                .foregroundStyle(theme.color.textPrimary)

                            Text("נצטרך את הפרטים האלו כדי לחבר אותך עם משתמשים אחרים")
                                .font(theme.typography.callout)
                                .foregroundStyle(theme.color.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, theme.spacing.xl)

                        VStack(alignment: .leading, spacing: theme.spacing.md) {
                            // Phone
                            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                                Text("מספר טלפון")
                                    .sectionHeader()
                                ThemedInputField(icon: "phone.fill", placeholder: "05X-XXXXXXX", text: $phone,
                                                 keyboard: .phonePad, textContentType: .telephoneNumber)
                            }

                            // Address
                            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                                Text("כתובת")
                                    .sectionHeader()
                                AddressAutocompleteField(placeholder: "רחוב, עיר", text: $address)
                            }

                            if let error = errorMessage {
                                Text(error)
                                    .foregroundStyle(theme.color.error)
                                    .font(theme.typography.footnote)
                            }
                        }
                        .padding(.horizontal, theme.spacing.lg)

                        Spacer(minLength: theme.spacing.xl)

                        Button {
                            if phone.count < 9 {
                                errorMessage = "נא להזין מספר טלפון תקין"
                                return
                            }
                            if address.isEmpty {
                                errorMessage = "נא להזין כתובת"
                                return
                            }
                            saveDetails()
                        } label: {
                            if isLoading {
                                LottieProgressView(size: 36)
                            } else {
                                Text("המשך")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isValid || isLoading)
                        .padding(.horizontal, theme.spacing.lg)
                        .padding(.bottom, theme.spacing.xl)
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
    
    func saveDetails() {
        guard let uid = appState.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await appState.db.collection("users").document(uid).updateData([
                    "phone": phone,
                    "address": address
                ])
                
                await MainActor.run {
                    appState.currentUser?.phone = phone
                    appState.currentUser?.address = address
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "שגיאה בשמירת הנתונים. אנא נסה שוב."
                    isLoading = false
                }
            }
        }
    }
}
