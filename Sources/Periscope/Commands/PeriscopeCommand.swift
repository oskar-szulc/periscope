import ArgumentParser

struct PeriscopeRoot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "periscope",
        abstract: "A headless browser CLI for agents.",
        version: "0.1.0",
        subcommands: [
            Navigate.self, Back.self, Forward.self,
            Reload.self, CurrentURL.self, History.self,
            Extract.self, HTML.self, Attr.self, Links.self, Table.self,
            Click.self, Fill.self, SelectOption.self, Check.self,
            Uncheck.self, Submit.self, Scroll.self, Hover.self,
            Screenshot.self,
            Eval.self,
            Session.self,
            Cookie.self,
            Login.self,
            Query.self, Find.self,
            Wait.self, Elements.self,
            Serve.self, DaemonGroup.self,
        ]
    )
}
