import Foundation

/// A page that is a bot challenge rather than the content asked for.
///
/// Raw values are the wire spelling: they appear in `state` output, in the
/// `BLOCKED` error message, and scripts branch on them.
enum BlockKind: String, Sendable, Codable {
    case googleCaptcha = "google-captcha"
    case duckduckgoChallenge = "duckduckgo-challenge"
    case cloudflareChallenge = "cloudflare-challenge"
}

/// Recognises the challenge pages agents actually run into. Kept deliberately
/// narrow: a generic "has a reCAPTCHA iframe" rule would flag every login form.
enum BlockDetector {
    static func classify(url: String, title: String, text: String) -> BlockKind? {
        let url = url.lowercased()
        let title = title.lowercased()
        let text = text.lowercased()

        // "Verifying your request" is Google's soft interstitial: it never
        // clears for a session whose cookies came from a different user agent.
        if url.contains("google."),
            url.contains("/sorry/") || text.contains("unusual traffic from your computer network")
                || text.contains("verifying your request")
        {
            return .googleCaptcha
        }
        if url.contains("duckduckgo.com"), text.contains("bots use duckduckgo too") {
            return .duckduckgoChallenge
        }
        if title.hasPrefix("just a moment")
            || text.contains("verifying you are human")
            || text.contains("checking your browser before accessing")
        {
            return .cloudflareChallenge
        }
        return nil
    }
}
