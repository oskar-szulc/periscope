# periscope

A browser for AI agents, driven from the shell, running on the WebKit engine
already in macOS: the same engine, user agent and TLS stack as Safari.

Chromium-based tools and custom engines are easy for bot checks to spot.
periscope is Safari to the site, and it keeps named sessions alive between
commands, so an agent can navigate, read, act and come back to the same page.

```text
$ periscope navigate https://books.toscrape.com/ --session demo
Navigated to: All products | Books to Scrape - Sandbox
URL: https://books.toscrape.com/
Status: 200 · Text: 1,809 chars · HTML: 50,989 chars

$ periscope extract --session demo --json --fields itemSelector,next
{"itemSelector":"ol.row > li.col-lg-3.col-md-3.col-sm-4.col-xs-6","next":"https://books.toscrape.com/catalogue/page-2.html"}

$ periscope state --session demo --match Tipping
Actions (1):
  @58  ... > article > h3 > a  a  "Tipping the Velvet" -> catalogue/tipping-the-velvet_999/index.html

$ periscope click @58 --session demo
Navigated to: Tipping the Velvet | Books to Scrape - Sandbox
```

`extract` with no arguments needs no AI model: it returns the page's schema.org
data, its repeated records (cards, results, table rows) and the next-page link.
Each record looks like
`{"text": ["Tipping the Velvet", "£53.74", "In stock", …], "links": [...], "image": "…"}`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/oskar-szulc/periscope/main/install.sh | sh
periscope install-skill            # teach Claude Code (or --codex, --all, --global)
```

Or build from source (Xcode 26):

```bash
swift build -c release
rm -f /usr/local/bin/periscope && cp .build/release/periscope /usr/local/bin/periscope
```

Remove, then copy: macOS caches a code signature per inode and kills a binary
overwritten in place. After upgrading, `periscope daemon stop` so the next
command starts the new build.

## What it does

- **Reads pages the way agents need them:** `text` (markdown), `state` (content
  plus every actionable element with a selector and an `@N`), `extract`, `links`,
  `table`, `requests` (every fetch/XHR and its status), `console`.
- **Acts like a person:** `click`, `fill`, `select`, `check`, `hover`; `type`
  sends real key events and `mouse` real clicks, drags and scrolls, which the
  page sees as trusted. Targets are CSS or what a person sees: `text:Next`,
  `label:Email`, `role:button name=Sign in`, or `@N` from `state`.
- **Knows when it is blocked:** Google's CAPTCHA and "verifying" pages,
  DuckDuckGo's and Cloudflare's challenges exit 5 instead of passing for
  content. `navigate --wait-challenge 20` lets a self-clearing challenge pass.
- **Keeps sessions:** a daemon holds one live page per `--session`, so state,
  cookies and SPA routes survive between commands; sessions are also saved to
  disk. `login` and `show` hand a page to a person (a login, a CAPTCHA) and take
  it back.
- **Stays fast:** `--resource-mode lean` skips images, media and fonts.

The full reference, written for agents, is [PERISCOPE.md](PERISCOPE.md).

## Requirements and limits

- **macOS 26 or newer**, in a logged-in desktop session. It does not run on
  Linux, in Docker or on a headless server.
- **The display must be on** while it works. With the display asleep or the
  screen locked, macOS stops page rendering callbacks. Wrap unattended runs in
  `caffeinate -d`.
- **Not inside a sandbox.** A shell sandbox (like Claude Code's Bash tool) blocks
  the window server; periscope says so and exits 3 rather than hanging.
- **Apple Intelligence** is used only by `query`, `find` and `extract` with
  field names. Everything else works without it.

## How it works

The CLI is a thin client. Each command goes over a unix socket to a daemon,
started on demand, that owns a hidden WebKit window per session. The window
stays one pixel on screen so macOS treats the page as visible. Without that,
WebKit pauses rendering and pages that draw on a frame, such as React
streaming, never finish. `--no-daemon`, or an unreachable daemon, runs the
command in-process instead, which works but reloads the page every time.

`PERISCOPE_DIR` keeps a project's sessions (and its own daemon) apart from
`~/.periscope`. `periscope daemon log` shows what the daemon reported.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
