import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @Environment(\.layoutDirection) var layoutDirection
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showSignUp = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.cyan.opacity(0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        VStack(spacing: 12) {
                            Text("דוגסיטר")
                                .font(.system(size: 54, weight: .heavy, design: .rounded))
                                .foregroundColor(.blue)
                                .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 5)
                            
                            Text("האפליקציה הטובה ביותר לחיית עזרך")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 60)
                        .padding(.bottom, 20)
                        
                        VStack(spacing: 20) {
                            CustomTextField(icon: "envelope.fill", placeholder: "אימייל", text: $email, keyboardType: .emailAddress)
                            
                            HStack {
                                Image(systemName: "lock.fill").foregroundColor(.gray)
                                SecureField("סיסמה", text: $password)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(15)
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        }
                        .padding(.horizontal, 30)
                        
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        Button(action: handleLogin) {
                            HStack {
                                Text("התחבר")
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
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                        
                        Button(action: resetPassword) {
                            Text("שכחתי סיסמה")
                                .foregroundColor(.blue)
                                .font(.subheadline)
                        }
                        
                        Button(action: { showSignUp = true }) {
                            Text("משתמש חדש? הירשם כאן")
                                .foregroundColor(.blue)
                                .font(.subheadline)
                        }
                        .navigationDestination(isPresented: $showSignUp) {
                            SignUpView()
                        }
                        
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
