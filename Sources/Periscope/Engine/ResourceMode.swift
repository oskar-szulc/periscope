import ArgumentParser
import WebKit

/// `--resource-mode`: `lean` blocks images, media and fonts, which scraping
/// never reads and which dominate load time on heavy pages.
enum ResourceMode: String, ExpressibleByArgument, CaseIterable, Sendable {
    case full, lean

    /// Compiled once per process and cached by WebKit on disk by identifier.
    @MainActor private static var leanRules: WKContentRuleList?

    @MainActor static func leanRuleList() async -> WKContentRuleList? {
        if let leanRules { return leanRules }
        let json = #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]"#
        leanRules = try? await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: "periscope-lean-v1", encodedContentRuleList: json)
        return leanRules
    }
}
