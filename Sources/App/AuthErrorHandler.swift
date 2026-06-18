import Foundation
import FirebaseAuth
import SecurityKit

struct AuthErrorHandler {
    // F-19 / F-20: map auth errors to safe, user-facing messages.
    //  - userNotFound and wrongPassword collapse into one message so an attacker
    //    cannot tell whether an email is registered (account enumeration).
    //  - unknown errors return a generic message and never leak the backend's
    //    raw `localizedDescription`.
    static func handle(error: Error) -> String {
        let code = (error as NSError).code
        // Keep the dedicated "account disabled" message; delegate the rest.
        if code == AuthErrorCode.userDisabled.rawValue {
            return "חשבון זה הושבת."
        }
        return AuthErrorMapper.userFacing(code: code)
    }
}
