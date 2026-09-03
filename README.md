# Periscope

A headless browser CLI for AI agents, built on WebKit (Safari's engine).

Unlike Playwright/Puppeteer which use Chromium, Periscope uses the native macOS WebKit engine. This means it presents a genuine Safari browser fingerprint that bot detection systems (Cloudflare, DataDome, PerimeterX) don't flag.

## Requirements

- macOS 26+
- Xcode 26+ (for building)

## Build

```bash
cd periscope
swift build -c release --disable-sandbox
```

The binary is at `.build/release/Periscope`.

## Install

```bash
cp .build/release/Periscope /opt/homebrew/bin/periscope
```

Or wherever you keep local binaries that's in your PATH.

## Quick Start

```bash
# Navigate and read content
periscope navigate "https://example.com" --session demo
periscope text --session demo

# Take a screenshot
periscope screenshot /tmp/page.png --session demo

# Execute JavaScript
periscope eval "document.title" --session demo

# Fill a form
periscope fill "#search" "query" --session demo
periscope click "#submit" --session demo

# Manual login (opens visible browser window)
periscope login "https://app.example.com/login" --session myapp
```

## How It Works

A background daemon holds a live `WebPage` per named session. The CLI is a thin
client that sends one command over a unix socket at `~/.periscope/run/sock` and
prints the reply, so commands after the first in a session reuse a browser that
is genuinely still open — no page reload, and JS state, SPA route and scroll
position all survive. The daemon starts on demand; you never launch it yourself.

Sessions are also flushed to `~/.periscope/sessions/<name>/` (cookies,
localStorage, last URL) when evicted or on shutdown, so they survive a reboot
and cold-start from there.

`--no-daemon` runs everything in-process instead: correct, but it rebuilds the
page from that snapshot on every command. It is the automatic fallback whenever
the daemon cannot be reached, so periscope never hard-fails on daemon trouble.

## Agent Integration

See [PERISCOPE.md](PERISCOPE.md) for the full command reference designed for AI agents.

To make periscope available to agents, point them to PERISCOPE.md or add it to their context. For Claude Code, add to your CLAUDE.md:

```
For web browsing, use the `periscope` CLI. Reference: /path/to/periscope/PERISCOPE.md
```

## All Commands

```
navigate <url>        Go to URL
back / forward        History navigation
reload                Reload page
url                   Print current URL
history               Print history

state                 URL, content and every actionable selector
text [selector]       Content as markdown
html [selector]       Raw HTML
attr <sel> <attr>     Get attribute value
links                 List all links
table <selector>      Extract table

click <selector>      Click element
fill <sel> <value>    Set input value
select <sel> <value>  Choose <select> option
check / uncheck       Toggle checkbox
submit [selector]     Submit form
scroll <target>       Scroll (up/down/top/bottom/selector)
hover <selector>      Hover element

screenshot [path]     Take screenshot
eval <code>           Execute JavaScript

session list/delete/export/import
cookie list/set/delete
login <url>           Manual login with visible browser
wait <strategy>       Wait for condition
elements <selector>   Inspect matching elements

query <question>      Ask about the page (Apple Intelligence)
find <description>    Description -> CSS selector

daemon status/stop    Inspect or stop the session daemon
serve                 Run the daemon in the foreground
```

## License

Private.
