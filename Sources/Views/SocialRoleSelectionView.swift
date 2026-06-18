import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SocialRoleSelectionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    @State private var selectedRole: UserRole = .sitter
    @State private var address = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    // Auth metadata context derived securely during this session
    let uid: String
    let email: String
    
    var body: some View {
        ZStack {
            BrandGradient()

            VStack(spacing: theme.spacing.xl) {
                Text("דוגסיטר")
                    .font(theme.typography.display)
                    .foregroundStyle(theme.color.accent)
                    .multilineTextAlignment(.center)
                    .padding(.top, 50)

                Text("איך תרצה להשתמש באפליקציה?")
                    .font(theme.typography.title2)
                    .foregroundStyle(theme.color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, theme.spacing.xl)

                VStack(spacing: theme.spacing.md) {
                    roleButton(.sitter, icon: "pawprint.fill", title: "אני מטפל")
                    roleButton(.owner, icon: "person.fill", title: "אני בעל כלב")
                }
                .padding(.horizontal, theme.spacing.xl)

                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text("איפה אתה גר?")
                        .sectionHeader()
                    AddressAutocompleteField(placeholder: "כתובת (למשל: רחוב דיזנגוף 50, תל אביב)", text: $address)
                }
                .padding(.horizontal, theme.spacing.xl)
                .padding(.top, theme.spacing.xs)

                Button("המשך", action: completeRegistration)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, theme.spacing.xl)
                    .padding(.top, theme.spacing.xs)
                    .disabled(isLoading)

                if isLoading {
                    LottieProgressView(size: 80)
                        .padding(.top, theme.spacing.lg)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(theme.color.error)
                        .font(theme.typography.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, theme.spacing.xs)
                }

                Spacer()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
    
    @ViewBuilder
    private func roleButton(_ role: UserRole, icon: String, title: String) -> some View {
        let isSelected = selectedRole == role
        Button {
            selectedRole = role
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.title)
                Text(title)
                    .font(theme.typography.title3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing.lg)
            .foregroundStyle(isSelected ? theme.color.textOnAccent : theme.color.accent)
            .background {
                if isSelected {
                    LinearGradient(colors: theme.color.accentGradient, startPoint: .leading, endPoint: .trailing)
                } else {
                    theme.color.surface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                    .stroke(theme.color.accent.opacity(isSelected ? 0 : 0.4), lineWidth: 1.5)
            )
            .elevation(isSelected ? theme.elevation.card : theme.elevation.none)
        }
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    private func completeRegistration() {
        guard !address.isEmpty else {
            errorMessage = "נא להזין כתובת"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        // Extract display name or fallback
        let rawDisplayName = Auth.auth().currentUser?.displayName ?? "משתמש חדש"
        let fallbackUsername = "@" + (email.split(separator: "@").first.map(String.init) ?? "user")
        
        let data: [String: Any] = [
            "id": uid,
            "name": rawDisplayName,
            "email": email,
            "address": address,
            "role": selectedRole.rawValue,
            "username": fallbackUsername,
            "createdAt": Timestamp()
        ]
        
        Firestore.firestore().collection("users").document(uid).setData(data) { err in
            DispatchQueue.main.async {
                self.isLoading = false
                if let err = err {
                    self.errorMessage = "שגיאה ביצירת פרופיל. אנא נסה שוב."
                    return
                }
                // Escalate role securely inside AppState driving navigation natively
                self.appState.currentUserRole = selectedRole
            }
        }
    }
}
