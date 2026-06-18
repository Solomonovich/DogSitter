import Foundation

/// F-19 / F-20: map raw Firebase auth error codes to safe, user-facing messages.
/// `userNotFound` and `wrongPassword` collapse into one message so an attacker
/// cannot enumerate which emails are registered, and unknown errors never leak
/// the backend's `localizedDescription`.
public enum AuthErrorKind: Equatable {
    case wrongCredentials   // userNotFound + wrongPassword, collapsed
    case emailInUse
    case weakPassword
    case invalidEmail
    case networkError
    case tooManyRequests
    case unknown
}

public enum AuthErrorMapper {
    // Stable Firebase `AuthErrorCode` raw values.
    static let codeEmailInUse = 17007
    static let codeInvalidEmail = 17008
    static let codeWrongPassword = 17009
    static let codeTooManyRequests = 17010
    static let codeUserNotFound = 17011
    static let codeNetwork = 17020
    static let codeWeakPassword = 17026

    public static func classify(code: Int) -> AuthErrorKind {
        switch code {
        case codeWrongPassword, codeUserNotFound: return .wrongCredentials
        case codeEmailInUse: return .emailInUse
        case codeWeakPassword: return .weakPassword
        case codeInvalidEmail: return .invalidEmail
        case codeNetwork: return .networkError
        case codeTooManyRequests: return .tooManyRequests
        default: return .unknown
        }
    }

    public static func message(for kind: AuthErrorKind) -> String {
        switch kind {
        case .wrongCredentials: return "האימייל או הסיסמה שגויים."
        case .emailInUse: return "לא ניתן להשלים את הפעולה. נסה להתחבר או להשתמש באימייל אחר."
        case .weakPassword: return "הסיסמה חלשה מדי. בחר סיסמה חזקה יותר."
        case .invalidEmail: return "כתובת האימייל אינה תקינה."
        case .networkError: return "בעיית רשת. בדוק את החיבור ונסה שוב."
        case .tooManyRequests: return "יותר מדי ניסיונות. נסה שוב מאוחר יותר."
        case .unknown: return "אירעה שגיאה. אנא נסה שוב."
        }
    }

    /// Convenience: raw code -> user-facing message.
    public static func userFacing(code: Int) -> String {
        message(for: classify(code: code))
    }
}
