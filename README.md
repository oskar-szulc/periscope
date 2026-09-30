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
curl -fsSL https://raw.githubusercontent.com/oskar-szulc/periscope/main/install.sh | sh
periscope install-skill    # adds the agent skill to this project
```

To build from source instead (Xcode 26): `swift build -c release`, then copy
`.build/release/periscope` onto your PATH.

## What you can do

- **Read:** `text`, `state` (content plus every clickable element), `extract`, `links`, `screenshot`
- **Act:** `click`, `fill`, `type`, `select`, `scroll`, `mouse`, targeting CSS or what a person sees (`text:Next`, `label:Email`)
- **Stay logged in:** named sessions persist; `login` and `show` let you take over the window
- **Know when you're blocked:** CAPTCHA and bot-check pages exit with code 5

Full reference: [PERISCOPE.md](PERISCOPE.md).

## Requirements

- macOS 26 or newer, in a logged-in desktop session with the display on
- Not inside a shell sandbox (periscope exits with a message if it is)

## License

[MIT](LICENSE). Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).
