import Foundation
import AuthenticationServices

/// Presents Grow's hosted payment page in a system web-auth session and resolves
/// when it returns to the `dogsitter://` callback. Used by CardCaptureCoordinator
/// for the Grow rail (Israeli). ASWebAuthenticationSession gives us the deep-link
/// callback for free, so no WKWebView plumbing is needed.
@MainActor
enum GrowWebAuth {
    private final class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            CardCaptureCoordinator.topViewController()?.view.window ?? ASPresentationAnchor()
        }
    }
    private static let provider = ContextProvider()

    /// Returns the callback URL the hosted page redirected to, or nil if cancelled.
    static func present(url: URL) async -> URL? {
        await withCheckedContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "dogsitter") { callbackURL, _ in
                cont.resume(returning: callbackURL)
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}
