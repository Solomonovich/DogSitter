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
        } else if let user = appState.currentUser, (user.phone == nil || user.phone!.isEmpty || user.address == nil || user.address!.isEmpty) {
            ContactDetailsOnboardingView()
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
                    LottieProgressView(size: 100)
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

struct ContactDetailsOnboardingView: View {
    @EnvironmentObject var appState: AppState
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
                LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.cyan.opacity(0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text("דוגסיטר")
                                .font(.system(size: 54, weight: .heavy, design: .rounded))
                                .foregroundColor(.blue)
                                .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 5)
                            
                            Text("פרטי יצירת קשר")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text("נצטרך את הפרטים האלו כדי לחבר אותך עם משתמשים אחרים")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 40)
                        
                        VStack(alignment: .trailing, spacing: 20) {
                            // Phone
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("מספר טלפון")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack {
                                    Image(systemName: "phone.fill").foregroundColor(.gray)
                                    TextField("05X-XXXXXXX", text: $phone)
                                        .keyboardType(.phonePad)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(15)
                                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                            }
                            
                            // Address
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("כתובת")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                AddressAutocompleteField(placeholder: "רחוב, עיר", text: $address)
                            }
                            
                            if let error = errorMessage {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.system(size: 14))
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 40)
                        
                        Button(action: {
                            if phone.count < 9 {
                                errorMessage = "נא להזין מספר טלפון תקין"
                                return
                            }
                            if address.isEmpty {
                                errorMessage = "נא להזין כתובת"
                                return
                            }
                            saveDetails()
                        }) {
                            HStack {
                                if isLoading {
                                    LottieProgressView(size: 36)
                                } else {
                                    Text("המשך")
                                        .font(.headline)
                                        .bold()
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(15)
                            .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                            .opacity(isValid ? 1.0 : 0.5)
                        }
                        .disabled(!isValid || isLoading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
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
                    errorMessage = "שגיאה בשמירת הנתונים: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}
