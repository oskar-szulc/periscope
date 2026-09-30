import ArgumentParser

struct PeriscopeRoot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "periscope",
        abstract: "A headless browser CLI for agents.",
        discussion: """
            Agents: `periscope docs` prints the full reference; `periscope install-skill` adds \
            the agent skill to a project. Start with `periscope navigate <url> --session <name>`, \
            then `state`, `text` or `extract`.
            """,
        version: "0.2.3",
        subcommands: [
            Navigate.self, Back.self, Forward.self,
            Reload.self, CurrentURL.self, History.self,
            Extract.self, ExtractData.self, HTML.self, Attr.self, Links.self, Table.self,
            Click.self, Fill.self, SelectOption.self, Check.self,
            Uncheck.self, Submit.self, Scroll.self, Hover.self, Mouse.self, TypeText.self,
            Screenshot.self,
            Eval.self,
            Session.self,
            Cookie.self,
            Login.self, Show.self, Hide.self,
            Query.self, Find.self,
            Wait.self, Elements.self, State.self,
            Requests.self, Console.self,
            Serve.self, DaemonGroup.self, InstallSkill.self, Docs.self, MCP.self,
        ]
    )
}
