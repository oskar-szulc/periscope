# periscope

A command-line browser for AI agents on macOS. It runs Safari's engine (WebKit),
so websites see a normal Safari, and it keeps sessions open between commands.

```bash
periscope navigate https://books.toscrape.com/ --session demo
periscope text --session demo        # the page as markdown
periscope extract --session demo     # the page's records as JSON
periscope click "text:Next" --session demo
```

## Install

```bash
brew install oskar-szulc/tap/periscope
periscope install-skill    # adds the agent skill to this project
```

Without Homebrew: `curl -fsSL https://raw.githubusercontent.com/oskar-szulc/periscope/main/install.sh | sh`

To build from source instead (Xcode 26): `swift build -c release`, then copy
`.build/release/periscope` onto your PATH.

### For agents

- **Claude Code:** `/plugin marketplace add oskar-szulc/periscope`, then `/plugin install periscope@periscope`
- **Codex, Cursor and others:** `npx skills add oskar-szulc/periscope`
- **MCP clients:** the command is `periscope mcp`, e.g. `claude mcp add periscope -- periscope mcp`, or in a JSON config: `{"mcpServers": {"periscope": {"command": "periscope", "args": ["mcp"]}}}`
- **Any agent with a shell:** `periscope docs` prints the full reference

## Reading a page

| Command | Returns | Use it to |
|---|---|---|
| `text` | The page's main content as markdown, links included | Read an article or a post |
| `state` | URL, title, headings, the start of the content, and every clickable element with a selector and a number (`@3`) | Decide what to click or fill next |
| `extract` | JSON: the page's repeated items (cards, results, table rows), its structured data, and the next-page link | Scrape a list of jobs, products or results |
| `links` | Every link on the page as an absolute URL (`--match` to filter) | Collect URLs to visit next |
| `screenshot` | A PNG of the page as displayed | See the layout, or check visual content |

## What else you can do

- **Act:** `click`, `fill`, `type`, `select`, `scroll`, `mouse`, targeting CSS or what a person sees (`text:Next`, `label:Email`)
- **Stay logged in:** named sessions persist; `login` and `show` let you take over the window
- **Know when you're blocked:** CAPTCHA and bot-check pages exit with code 5

Full reference: [PERISCOPE.md](PERISCOPE.md).

## Requirements

- macOS 26 or newer, in a logged-in desktop session with the display on
- Not inside a shell sandbox (periscope exits with a message if it is)

## License

[MIT](LICENSE). Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).
