import Foundation
import FirebaseAuth

struct AuthErrorHandler {
    static func handle(error: Error) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case AuthErrorCode.invalidEmail.rawValue:
            return "כתובת האימייל אינה תקינה."
        case AuthErrorCode.wrongPassword.rawValue:
            return "הסיסמה שהזנת שגויה."
        case AuthErrorCode.userNotFound.rawValue:
            return "לא נמצא משתמש עם אימייל זה."
        case AuthErrorCode.userDisabled.rawValue:
            return "חשבון זה הושבת."
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "האימייל הזה כבר נמצא בשימוש המערכת."
        case AuthErrorCode.weakPassword.rawValue:
            return "הסיסמה חלשה מדי. אנא בחר סיסמה של 6 תווים ומעלה."
        case AuthErrorCode.networkError.rawValue:
            return "אין חיבור לאינטרנט. אנא בדוק את החיבור שלך ונסה שוב."
        default:
            return "אירעה שגיאה: \(error.localizedDescription)"
        }
    }
}
