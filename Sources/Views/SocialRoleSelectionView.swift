import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SocialRoleSelectionView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedRole: UserRole = .sitter
    @State private var address = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    // Auth metadata context derived securely during this session
    let uid: String
    let email: String
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.orange.opacity(0.1), Color.blue.opacity(0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Text("דוגסיטר")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 50)
                
                Text("איך תרצה להשתמש באפליקציה?")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                
                VStack(spacing: 20) {
                    Button(action: {
                        selectedRole = .sitter
                    }) {
                        HStack {
                            Image(systemName: "pawprint.fill")
                                .font(.title)
                            Text("אני מטפל")
                                .font(.title3.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .opacity(selectedRole == .sitter ? 1.0 : 0.6)
                    }
                    
                    Button(action: {
                        selectedRole = .owner
                    }) {
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.title)
                            Text("אני בעל כלב")
                                .font(.title3.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .opacity(selectedRole == .owner ? 1.0 : 0.6)
                    }
                }
                .padding(.horizontal, 40)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("איפה אתה גר?")
                        .font(.headline)
                        .padding(.horizontal, 5)
                    AddressAutocompleteField(placeholder: "כתובת (למשל: רחוב דיזנגוף 50, תל אביב)", text: $address)
                }
                .padding(.horizontal, 30)
                .padding(.top, 10)
                
                Button(action: completeRegistration) {
                    Text("המשך")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }
                .padding(.horizontal, 40)
                .padding(.top, 10)
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(1.5)
                        .padding(.top, 20)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 10)
                }
                
                Spacer()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
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
                    self.errorMessage = "שגיאה ביצירת פרופיל: \(err.localizedDescription)"
                    return
                }
                // Escalate role securely inside AppState driving navigation natively
                self.appState.currentUserRole = selectedRole
            }
        }
    }
}
