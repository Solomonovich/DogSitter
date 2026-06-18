import Foundation

/// F-21: only render remote images served from hosts the app trusts. Message
/// `photoURL`s are client-controlled, so an attacker could otherwise point a
/// bubble at their own server and harvest viewers' IPs (a tracking beacon).
public enum ImageHostPolicy {
    /// Hosts the app is allowed to load remote images from (the app's Cloudinary cloud).
    public static let allowedHosts: Set<String> = ["res.cloudinary.com"]

    /// True only for `https` URLs whose host is an allowed host (or a subdomain of one).
    public static func isAllowed(_ urlString: String?, allowedHosts: Set<String> = allowedHosts) -> Bool {
        guard let urlString,
              let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else { return false }
        return allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
