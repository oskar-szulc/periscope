import ArgumentParser

struct PeriscopeRoot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "periscope",
        abstract: "A headless browser CLI for agents.",
        version: "0.1.0",
        subcommands: [
            Navigate.self, Back.self, Forward.self,
            Reload.self, CurrentURL.self, History.self,
        ]
    )
}
