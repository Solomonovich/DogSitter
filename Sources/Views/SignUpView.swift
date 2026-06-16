import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var fullName = ""
    @State private var email = ""
    @State private var address = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedRole: UserRole = .sitter
    @State private var errorMessage = ""
    @State private var isLoading = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.cyan.opacity(0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 12) {
                        Text("הרשמה")
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundColor(.blue)
                        
                        Text("הצטרף למשפחת דוגסיטר")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 10)
                    
                    VStack(spacing: 20) {
                        CustomTextField(icon: "person.fill", placeholder: "שם מלא", text: $fullName)
                        AddressAutocompleteField(placeholder: "כתובת", text: $address)
                        CustomTextField(icon: "envelope.fill", placeholder: "אימייל", text: $email, keyboardType: .emailAddress)
                        
                        HStack {
                            Image(systemName: "lock.fill").foregroundColor(.gray)
                            SecureField("סיסמה (לפחות 6 תווים)", text: $password)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(15)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        
                        HStack {
                            Image(systemName: "lock.fill").foregroundColor(.gray)
                            SecureField("אימות סיסמה", text: $confirmPassword)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(15)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        
                        VStack(alignment: .trailing, spacing: 10) {
                            Text("בחר את התפקיד שלך:")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            
                            Picker("תפקיד", selection: $selectedRole) {
                                Text("אני מטפל").tag(UserRole.sitter)
                                Text("אני בעל כלב").tag(UserRole.owner)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    .padding(.horizontal, 30)
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Button(action: handleSignUp) {
                        HStack {
                            Text("הירשם")
                                .font(.title2.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .cornerRadius(25)
                        .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal, 30)
                    .disabled(isLoading)
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("כבר יש לך חשבון? התחבר כאן")
                            .foregroundColor(.blue)
                            .font(.subheadline)
                    }
                    .padding(.top, 10)
                    
                    SocialAuthButtonsView(isLoading: $isLoading)
                    
                    Spacer()
                }
                }
                
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    LottieProgressView(size: 100)
                }
            }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationBarHidden(true)
    }
    
    private func handleSignUp() {
        guard !fullName.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "אנא מלא את כל השדות."
            return
        }
        
        guard !address.isEmpty else {
            errorMessage = "נא להזין כתובת"
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
            
            // Generate clean username prefixing from email
            let username = "@" + (email.split(separator: "@").first.map(String.init) ?? "user")
            
            let data: [String: Any] = [
                "id": uid,
                "name": self.fullName,
                "email": self.email,
                "address": self.address,
                "role": self.selectedRole.rawValue,
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

// Reusable TextField for Login/Signup
struct CustomTextField: View {
    var icon: String
    var placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gray)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}
