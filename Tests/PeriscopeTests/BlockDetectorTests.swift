import Foundation
import Testing

@testable import Periscope

@Suite("BlockDetector")
struct BlockDetectorTests {
    @Test func googleSorryPageByURL() {
        let kind = BlockDetector.classify(
            url: "https://www.google.com/sorry/index?continue=https://www.google.com/search%3Fq%3Dx",
            title: "https://www.google.com/search?q=x",
            text: "About this page Our systems have detected unusual traffic from your computer network.")
        #expect(kind == .googleCaptcha)
    }

    @Test func googleUnusualTrafficByTextEvenOnSearchURL() {
        let kind = BlockDetector.classify(
            url: "https://www.google.com/search?q=x",
            title: "",
            text:
                "Our systems have detected unusual traffic from your computer network. This page checks to see if it's really you"
        )
        #expect(kind == .googleCaptcha)
    }

    @Test func googleVerifyingInterstitial() {
        let kind = BlockDetector.classify(
            url: "https://www.google.com/search?q=site%3Ax.com",
            title: "site:x.com - Google Search",
            text: "Sign in\nVerifying your request\nYou'll be able to continue in a few seconds. Don't refresh this page.")
        #expect(kind == .googleCaptcha)
    }

    @Test func duckduckgoChallenge() {
        let kind = BlockDetector.classify(
            url: "https://html.duckduckgo.com/html/?q=x",
            title: "DuckDuckGo",
            text:
                "Unfortunately, bots use DuckDuckGo too. Please complete the following challenge to confirm this search was made by a human."
        )
        #expect(kind == .duckduckgoChallenge)
    }

    @Test func cloudflareInterstitialByTitle() {
        let kind = BlockDetector.classify(
            url: "https://example.com/",
            title: "Just a moment...",
            text: "example.com Verifying you are human. This may take a few seconds.")
        #expect(kind == .cloudflareChallenge)
    }

    @Test func ordinaryPageIsNotBlocked() {
        let kind = BlockDetector.classify(
            url: "https://www.google.com/search?q=weather+toronto",
            title: "weather toronto - Google Search",
            text: "Toronto, ON Weather 18°C Partly cloudy. Sorry we could not find your street.")
        #expect(kind == nil)
    }

    @Test func kindsHaveStableWireNames() {
        #expect(BlockKind.googleCaptcha.rawValue == "google-captcha")
        #expect(BlockKind.duckduckgoChallenge.rawValue == "duckduckgo-challenge")
        #expect(BlockKind.cloudflareChallenge.rawValue == "cloudflare-challenge")
    }
}

@Suite("PeriscopeError.blocked")
struct BlockedErrorTests {
    @Test func blockedExitsFiveWithStableCode() {
        let error = PeriscopeError.blocked(kind: .googleCaptcha, url: "https://www.google.com/sorry/index")
        #expect(error.exitCode == 5)
        #expect(error.wireCode == "BLOCKED")
        #expect(
            error.description
                == "Blocked by google-captcha at https://www.google.com/sorry/index")
    }

    @Test func blockedPayloadCarriesURL() {
        let payload = ErrorPayload(
            PeriscopeError.blocked(kind: .cloudflareChallenge, url: "https://example.com/"))
        #expect(payload.url == "https://example.com/")
        #expect(payload.code == "BLOCKED")
    }
}
