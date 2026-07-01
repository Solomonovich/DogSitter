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
    @Environment(\.theme) private var theme
    @StateObject private var socialManager = SocialAuthManager()
    @Binding var isLoading: Bool

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            divider

            HStack(spacing: theme.spacing.sm) {
                // Apple: background/foreground derive from tokens so the button stays
                // legible (near-white on dark, near-black on light) without literals.
                SocialLoginButton(
                    label: "Apple",
                    background: theme.color.textPrimary,
                    foreground: theme.color.background,
                    logo: {
                        Image(systemName: "applelogo")
                            .font(.system(size: 18, weight: .medium))
                    },
                    action: { socialManager.startSignInWithAppleFlow() }
                )

                SocialLoginButton(
                    label: "Google",
                    background: theme.color.surface,
                    foreground: theme.color.textPrimary,
                    border: theme.color.separator,
                    logo: { GoogleGMark() },
                    action: { socialManager.signInWithGoogle() }
                )
            }

            if !socialManager.errorMessage.isEmpty {
                Text(socialManager.errorMessage)
                    .foregroundStyle(theme.color.error)
                    .font(theme.typography.subheadline)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .onChange(of: socialManager.isProcessing) { isProcessing in
            isLoading = isProcessing
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var divider: some View {
        HStack(spacing: theme.spacing.sm) {
            line
            Text("או")
                .font(theme.typography.footnote)
                .foregroundStyle(theme.color.textSecondary)
            line
        }
    }

    private var line: some View {
        Rectangle()
            .fill(theme.color.separator)
            .frame(height: 1)
    }
}
