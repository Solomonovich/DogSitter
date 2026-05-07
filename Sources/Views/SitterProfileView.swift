import SwiftUI
import FirebaseAuth
import GoogleSignIn

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            Form {
                if let user = appState.currentUser {
                    Section(header: Text("פרטים אישיים")) {
                        HStack {
                            Text("שם מלא")
                            Spacer()
                            Text(user.name).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("שם משתמש")
                            Spacer()
                            Text(user.username).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("כתובת")
                            Spacer()
                            Text(user.address ?? "").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("טלפון")
                            Spacer()
                            Text(user.phone ?? "").foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        do {
                            GIDSignIn.sharedInstance.signOut()
                            try Auth.auth().signOut()
                        } catch {
                            print("Error signing out: \(error)")
                        }
                    }) {
                        Text("התנתק")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("הפרופיל שלי")
        }
    }
}
