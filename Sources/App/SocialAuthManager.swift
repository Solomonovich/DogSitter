import SwiftUI
import FirebaseAuth
import AuthenticationServices
import GoogleSignIn
import FirebaseCore
import CryptoKit
import FirebaseFirestore

class SocialAuthManager: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @Published var isProcessing = false
    @Published var errorMessage = ""
    
    // For Apple Sign In, we must hold onto the nonce
    private var currentNonce: String?
    
    // Helper to extract top UIViewController
    private func getRootViewController() -> UIViewController {
        guard let screen = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return UIViewController()
        }
        guard let root = screen.windows.first?.rootViewController else {
            return UIViewController()
        }
        // Iterate through presented view controllers if any
        var topController = root
        while let presented = topController.presentedViewController {
            topController = presented
        }
        return topController
    }
    
    // MARK: - Google Sign In
    func signInWithGoogle() {
        self.isProcessing = true
        self.errorMessage = ""
        
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            self.errorMessage = "שגיאה בתצורת הפרויקט עבור Google."
            self.isProcessing = false
            return
        }
        
        // Ensure GIDSignIn has configuration assigned securely via Firebase
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        let rootVC = getRootViewController()
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] signInResult, error in
            guard let self = self else { return }
            
            if let error = error as NSError? {
                self.isProcessing = false
                // Handle cancellation gracefully
                if error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
                    return
                }
                self.errorMessage = "שגיאה בהתחברות ל-Google: \(error.localizedDescription)"
                return
            }
            
            guard let user = signInResult?.user,
                  let idToken = user.idToken?.tokenString else {
                self.isProcessing = false
                self.errorMessage = "שגיאת אימות אישורי Google."
                return
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: user.accessToken.tokenString)
            
            Auth.auth().signIn(with: credential) { authResult, authError in
                if let authError = authError {
                    self.isProcessing = false
                    self.errorMessage = AuthErrorHandler.handle(error: authError)
                } else if let authResult = authResult {
                    if authResult.additionalUserInfo?.isNewUser == true {
                        let uid = authResult.user.uid
                        let email = authResult.user.email ?? ""
                        let name = authResult.user.displayName ?? "משתמש חדש"
                        let username = "@" + (email.split(separator: "@").first.map(String.init) ?? "user")
                        
                        let data: [String: Any] = [
                            "id": uid,
                            "name": name,
                            "email": email,
                            "role": UserRole.needsRole.rawValue,
                            "username": username,
                            "createdAt": Timestamp()
                        ]
                        
                        Task {
                            do {
                                try await AuthHelpers.createFirestoreUserWithRetry(uid: uid, data: data)
                                await MainActor.run {
                                    self.isProcessing = false
                                }
                            } catch {
                                await MainActor.run {
                                    self.isProcessing = false
                                    self.errorMessage = "שגיאה ביצירת הפרופיל. אנא נסה שוב."
                                }
                            }
                        }
                    } else {
                        self.isProcessing = false
                    }
                } else {
                    self.isProcessing = false
                }
            }
        }
    }
    
    // MARK: - Apple Sign In Setup
    func startSignInWithAppleFlow() {
        self.isProcessing = true
        self.errorMessage = ""
        
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            self.isProcessing = false
            self.errorMessage = "שגיאה בגישה לנתוני Apple ID."
            return
        }
        guard let nonce = currentNonce else {
            self.isProcessing = false
            return
        }
        guard let appleIDToken = appleIDCredential.identityToken else {
            self.isProcessing = false
            self.errorMessage = "המערכת לא הצליחה לקרוא את אסימון הזיהוי."
            return
        }
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            self.isProcessing = false
            return
        }
        
        let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
        
        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            guard let self = self else { return }
            
            if let error = error {
                self.isProcessing = false
                self.errorMessage = AuthErrorHandler.handle(error: error)
                return
            }
            
            if let authResult = authResult, authResult.additionalUserInfo?.isNewUser == true {
                let uid = authResult.user.uid
                let email = authResult.user.email ?? ""
                let name = authResult.user.displayName ?? "משתמש חדש"
                let username = "@" + (email.split(separator: "@").first.map(String.init) ?? "user")
                
                let data: [String: Any] = [
                    "id": uid,
                    "name": name,
                    "email": email,
                    "role": UserRole.needsRole.rawValue,
                    "username": username,
                    "createdAt": Timestamp()
                ]
                
                Task {
                    do {
                        try await AuthHelpers.createFirestoreUserWithRetry(uid: uid, data: data)
                        await MainActor.run {
                            self.isProcessing = false
                        }
                    } catch {
                        await MainActor.run {
                            self.isProcessing = false
                            self.errorMessage = "שגיאה ביצירת הפרופיל. אנא נסה שוב."
                        }
                    }
                }
            } else {
                self.isProcessing = false
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.isProcessing = false
        // Intercept standard cancellation
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            return
        }
        self.errorMessage = "שגיאה בהתחברות לאפל. אנא נסה שוב."
    }
    
    // MARK: - ASAuthorizationControllerPresentationContextProviding
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let screen = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return UIWindow()
        }
        return screen.windows.first ?? UIWindow()
    }
    
    // Utilities for nonce and hashing
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess { fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)") }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
    }
}

// Reusable Shared Social Buttons Component spanning LoginView & SignUpView
struct SocialAuthButtonsView: View {
    @StateObject private var socialManager = SocialAuthManager()
    @Binding var isLoading: Bool
    
    var body: some View {
        VStack(spacing: 15) {
            
            if !socialManager.errorMessage.isEmpty {
                Text(socialManager.errorMessage)
                    .foregroundColor(.red)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            

            
            Button(action: { socialManager.startSignInWithAppleFlow() }) {
                HStack {
                    Image(systemName: "applelogo")
                        .font(.title2)
                        .padding(.leading, 10)
                    Spacer()
                    Text("התחבר עם Apple")
                        .font(.headline)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(15)
            }
            .padding(.horizontal, 30)
            
            HStack(spacing: 15) {
                VStack { Divider().background(Color.gray.opacity(0.3)) }
                Text("או")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                VStack { Divider().background(Color.gray.opacity(0.3)) }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 10)
            
            Button(action: { socialManager.signInWithGoogle() }) {
                HStack {
                    // Note: Use a generic icon if specific assets aren't bundled. The user requests a Google Logo, "g.circle.fill" does not exist in SF Symbols, so we use a text G.
                    Text("G")
                        .font(.title2.bold())
                        .padding(.leading, 10)
                    Spacer()
                    Text("התחבר עם Google")
                        .font(.headline)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(15)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.horizontal, 30)
        }
        .onChange(of: socialManager.isProcessing) { isProcessing in
            isLoading = isProcessing
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
