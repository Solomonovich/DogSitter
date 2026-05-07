import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if !appState.isAuthenticated {
            LoginView()
        } else if appState.currentUserRole == .needsRole {
            if let currentUser = Auth.auth().currentUser {
                SocialRoleSelectionView(uid: currentUser.uid, email: currentUser.email ?? "unknown@apple.com")
            } else {
                LoginView()
            }
        } else if appState.currentUserRole == .none {
            VStack {
                if let errorMsg = appState.activeError {
                    Text(errorMsg)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button("נסה שוב") {
                        if let uid = Auth.auth().currentUser?.uid {
                            Task {
                                await appState.fetchCurrentProfile(uid: uid)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(1.5)
                    Text("טוען פרופיל...")
                        .foregroundColor(.secondary)
                        .padding(.top, 10)
                }
            }
        } else {
            MainTabView()
        }
    }
}
